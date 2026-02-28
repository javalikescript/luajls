(function() {
var global = window;
if (global._encodedRW) {
  console.log('/!\\ ignoring encoded ' + location.pathname);
  return;
}
global._encodedRW = true;

var p = location.pathname;
var i = p.indexOf('/', 4);
var base = p.substring(4, i);
var opts = p.substring(i + 1, p.indexOf('/', i + 1));
console.log('base path is ' + base + '/' + opts + ' (' + location.pathname + ')');

function b64ec(c) {
  return c === '-' ? '+' : (c === '_' ? '/' : '');
}
function b64e(s) {
  return btoa(s).replace(/[-_=]/g, b64ec);
}
function b64dc(c) {
  return c === '+' ? '-' : (c === '/' ? '_' : '');
}
function b64d(s) {
  return atob(s.replace(/[+\/]/g, b64dc));
}
function encodeHref(href) {
  var u = URL.parse(href);
  if (u) {
    if (u.protocol === 'https:' || u.protocol === 'http:') {
      var b = b64e(u.protocol + '//' + u.host);
      if (b !== base && opts.indexOf('o') !== -1) {
        return '/RW/static/not-found';
      }
      return '/RW/' + b + '/' + opts + u.pathname + u.search + u.hash;
    }
  } else if (href.charAt(0) === '/') {
    if (href.charAt(1) === '/') {
      var d = b64d(base);
      var i = d.indexOf(':');
      if (i) {
        return encodeHref(d.substring(0, i + 1) + href)
      }
    } else if (href.lastIndexOf('/RW/', 0) !== 0) {
      return '/RW/' + base + '/' + opts + href;
    }
  }
  return null;
}
function proxyHref(href, fallback) {
  var e = encodeHref('' + href);
  if (e) {
    console.log('replacing fetch ' + href + ' => ' + e);
    return e;
  }
  return fallback;
}
function blockTagName(tagName) {
  if (tagName) {
    var n = tagName.toUpperCase();
    if (n === 'SCRIPT' || n === 'IFRAME') {
      console.log('blocking element creation ' + n);
      return 'rw-' + tagName;
    }
  }
  return tagName;
}
function transformHtml(content) {
  if (content) {
    var c = content.toUpperCase();
    // TODO rewrite HTML when possible
    if (c.indexOf('HREF=') > 0 || c.indexOf('SRC=') > 0) {
      console.log('blocking HTML ' + content);
      return '';
    }
  }
  return content;
}

/*
 * Wrapping fetch and XMLHttpRequest to proxy URLs
 */
if (global.fetch) {
  var rawFetch = global.fetch;
  global.fetch = function(resource, options) {
    return rawFetch(proxyHref(resource instanceof Request ? resource.url : resource, resource), options);
  };
}
if (global.XMLHttpRequest) {
  var rawXHROpen = global.XMLHttpRequest.prototype.open;
  global.XMLHttpRequest.prototype.open = function(method, url, async, user, password) {
    return rawXHROpen.call(this, method, proxyHref(url, url), async, user, password);
  };
}

/*
 * Wrapping various element creation
 */
if (global.Document) {
  var rawCreateElement = global.Document.prototype.createElement;
  global.Document.prototype.createElement = function(tagName, options) {
    return rawCreateElement.call(this, blockTagName(tagName), options);
  };
  var rawCreateElementNS = global.Document.prototype.createElementNS;
  global.Document.prototype.createElementNS = function(nsUri, tagName, options) {
    return rawCreateElementNS.call(this, nsUri, blockTagName(tagName), options);
  };
  var rawInsertAdjacentHTML = global.Document.prototype.insertAdjacentHTML;
  global.Document.prototype.insertAdjacentHTML = function(position, input) {
    return rawInsertAdjacentHTML.call(this, position, transformHtml(input));
  };
  var rawWrite = global.Document.prototype.write;
  global.Document.prototype.write = function() {
    var args = [];
    for (var i = 0; i < arguments.length; i++) {
      args.push(transformHtml(arguments[i]));
    }
    rawWrite.apply(this, args);
  };
}
if (global.Element && Object.getOwnPropertyDescriptor) {
  var rawInner = Object.getOwnPropertyDescriptor(Element.prototype, 'innerHTML');
  if (rawInner && rawInner.set) {
    Object.defineProperty(Element.prototype, 'innerHTML', {
      configurable: true,
      enumerable: rawInner.enumerable,
      get: function () {
        return rawInner.get.call(this);
      },
      set: function (html) {
        rawInner.set.call(this, transformHtml(html));
      }
    });
  }
}

if (global.MutationObserver) {
  function getUrlAttributeName(node) {
    var n = node.nodeName.toUpperCase();
    // the original resource may have already been loaded
    if (n === 'SCRIPT' || n === 'IFRAME' || n === 'SOURCE' || n === 'TRACK' || n === 'EMBED') {
      return 'src';
    } else if (n === 'IMG') {
      var srcset = node.getAttribute('srcset');
      if (srcset) {
        node.removeAttribute('srcset');
        if (!node.hasAttribute('src')) {
          var i = srcset.indexOf(' ');
          if (i < 0) {
            i = srcset.indexOf(',');
          }
          if (i > 0) {
            node.setAttribute('src', srcset.substring(0, i));
          }
        }
      }
      return 'src';
    } else if (n === 'A' || n === 'LINK' || n === 'AREA' || n === 'BASE') {
      return 'href';
    } else if (n === 'FORM') {
      return 'action';
    }
    return null;
  }
  function processAttribute(node, name) {
    var value = node.getAttribute(name);
    if (value) {
      var v = encodeHref(value);
      if (v) {
        console.log('replacing ' + node.nodeName + '.' + name + ': ' + value + ' => ' + v);
        node.setAttribute(name, v);
      }
    }
  }
  function rewriteElement(node) {
    if (node.nodeName.toUpperCase().lastIndexOf('RW-', 0) === 0 && rawCreateElement) {
      console.log('blocked element detected ' + node.nodeName);
      var e = rawCreateElement.call(global.document, node.nodeName.substring(3));
      if (node.attributes) {
        for (var ai = 0; ai < node.attributes.length; ai++) {
          var attr = node.attributes[ai];
          var value = attr.value;
          var t = attr.name.toLowerCase();
          if (t === 'href' || t === 'src') {
            var v = encodeHref(value);
            if (v) {
              console.log('replacing ' + node.nodeName + '.' + attr.name + ': ' + value + ' => ' + v);
              value = v;
            }
          }
          e.setAttribute(attr.name, value);
        }
      }
      while (node.firstChild) {
        e.appendChild(node.firstChild);
      }
      if (node.parentNode) {
        node.parentNode.replaceChild(e, node);
        return true;
      }
    }
    return false;
  }
  function processElement(node) {
    if (rewriteElement(node)) {
      return;
    }
    var t = getUrlAttributeName(node);
    if (t) {
      processAttribute(node, t);
    }
    for (var i = 0; i < node.childElementCount; i++) {
      processElement(node.children[i]);
    }
  }
  function observerCb(mutationList, observer) {
    for (var i = 0; i < mutationList.length; i++) {
      var mutation = mutationList[i];
      if (mutation.type === 'childList') {
        for (var j = 0; j < mutation.addedNodes.length; j++) {
          var addedNode = mutation.addedNodes[j];
          if (addedNode.nodeType === 1) {
            processElement(addedNode);
          }
        }
      } else if (mutation.type === 'attributes') {
        var t = mutation.attributeName.toLowerCase();
        if (t === 'href' || t === 'src') {
          processAttribute(mutation.target, t);
        }
      }
    }
  }
  console.log('connecting observer');
  var observer = new MutationObserver(observerCb);
  observer.observe(document.getRootNode(), {attributes: true, childList: true, subtree: true});
  document.addEventListener('DOMContentLoaded', function() {
    setTimeout(function() {
      console.log('disconnecting observer');
      let mutationList = observer.takeRecords();
      observer.disconnect();
      if (mutationList.length > 0) {
        observerCb(mutationList);
      }
    }, 500);
  });
}
})();
part of angular;


typedef ParsedGetter(self, [locals]);
typedef ParsedSetter(self, value, [locals]);

typedef Getter([locals]);
typedef Setter(value, [locals]);

class BoundExpression {
  var _context;
  Expression expression;

  BoundExpression(this._context, Expression this.expression);

  call([locals]) => expression.eval(_context, locals);
  assign(value, [locals]) => expression.assign(_context, value, locals);
}

class Expression {
  ParsedGetter eval;
  ParsedSetter assign;
  String exp;
  List parts;

  Expression(ParsedGetter this.eval, [ParsedSetter this.assign]);

  bind(context) => new BoundExpression(context, this);

  get assignable => assign != null;
}

class Token {
  bool json;
  int index;
  String text;
  String string;
  Operator fn;
  // access fn as a function that doesn't take a or b values.
  Expression primaryFn;

  Token(this.index, this.text) {
    // default fn
    this.withFn((s, l, a, b) => text);
  }

  withFn(fn, [assignFn]) {
    this.fn = fn;
    this.primaryFn = new Expression(
        (s, [l]) => fn(s, l, null, null),
        assignFn);
  }

  withFn0(fn()) => withFn(op0(fn));

  withString(string) { this.string = string; }

  fn0() => primaryFn.eval(null, null);

  toString() => "Token($text)";
}

// TODO(deboer): Type this typedef further
typedef Operator(self, locals, Expression a, Expression b);

op0(fn()) => (_, _1, _2, _3) => fn();

String QUOTES = "\"'";
String DOT = ".";
String SPECIAL = "(){}[].,;:";
String JSON_SEP = "{,";
String JSON_OPEN = "{[";
String JSON_CLOSE = "}]";
String WHITESPACE = " \r\t\n\v\u00A0";
String EXP_OP = "Ee";
String SIGN_OP = "+-";

Operator NULL_OP = (_, _x, _0, _1) => null;
Operator NOT_IMPL_OP = (_, _x, _0, _1) { throw "Op not implemented"; };

toBool(x) {
  if (x is bool) return x;
  if (x is int || x is double) return x != 0;
  return false;
}

// Automatic type conversion.
autoConvertAdd(a, b) {
  // TODO(deboer): Support others.
  if (a is String && b is! String) {
    return a + b.toString();
  }
  if (a is! String && b is String) {
    return a.toString() + b;
  }
  return a + b;
}

Map<String, Operator> OPERATORS = {
  'undefined': NULL_OP,
  'true': (self, locals, a, b) => true,
  'false': (self, locals, a, b) => false,
  '+': (self, locals, aFn, bFn) {
    var a = aFn.eval(self, locals);
    var b = bFn.eval(self, locals);
    if (a != null && b != null) return autoConvertAdd(a, b);
    if (a != null) return a;
    if (b != null) return b;
    return null;
  },
  '-': (self, locals, a, b) {
    assert(a != null || b != null);
    var aResult = a != null ? a.eval(self, locals) : null;
    var bResult = b != null ? b.eval(self, locals) : null;
    return (aResult == null ? 0 : aResult) - (bResult == null ? 0 : bResult);
  },
  '*': (s, l, a, b) => a.eval(s, l) * b.eval(s, l),
  '/': (s, l, a, b) => a.eval(s, l) / b.eval(s, l),
  '%': (s, l, a, b) => a.eval(s, l) % b.eval(s, l),
  '^': (s, l, a, b) => a.eval(s, l) ^ b.eval(s, l),
  '=': NULL_OP,
  '==': (s, l, a, b) => a.eval(s, l) == b.eval(s, l),
  '!=': (s, l, a, b) => a.eval(s, l) != b.eval(s, l),
  '<': (s, l, a, b) => a.eval(s, l) < b.eval(s, l),
  '>': (s, l, a, b) => a.eval(s, l) > b.eval(s, l),
  '<=': (s, l, a, b) => a.eval(s, l) <= b.eval(s, l),
  '>=': (s, l, a, b) => a.eval(s, l) >= b.eval(s, l),
  '&&': (s, l, a, b) => toBool(a.eval(s, l)) && toBool(b.eval(s, l)),
  '||': (s, l, a, b) => toBool(a.eval(s, l)) || toBool(b.eval(s, l)),
  '&': (s, l, a, b) => a.eval(s, l) & b.eval(s, l),
  '|': NOT_IMPL_OP, //b(locals)(locals, a(locals))
  '!': (self, locals, a, b) => !toBool(a.eval(self, locals))
};

Map<String, String> ESCAPE = {"n":"\n", "f":"\f", "r":"\r", "t":"\t", "v":"\v", "'":"'", '"':'"'};

Expression ZERO = new Expression((_, [_x]) => 0);

stripTrailingNulls(List l) {
  while (l.length > 0 && l.last == null) {
    l.removeLast();
  }
  return l;
}

var _undefined_ = new Symbol("UNDEFINED");

// Returns a tuple [found, value]
_getterChild(value, childKey) {
  if (value is List && childKey is num) {
    if (childKey < value.length) {
      return value[childKey];
    }
  } else if (value is Map) {
    // TODO: We would love to drop the 'is Map' for a more generic 'is Getter'
    if (childKey is String && value.containsKey(childKey)) {
      return value[childKey];
    }
  } else {
    InstanceMirror instanceMirror = reflect(value);
    Symbol curSym = new Symbol(childKey);

    try {
      // maybe it is a member field?
      return instanceMirror.getField(curSym).reflectee;
    } on NoSuchMethodError catch (e) {
      // maybe it is a member method?
      if (instanceMirror.type.members.containsKey(curSym)) {
        MethodMirror methodMirror = instanceMirror.type.members[curSym];
        return _relaxFnArgs(([a0, a1, a2, a3, a4, a5]) {
          var args = stripTrailingNulls([a0, a1, a2, a3, a4, a5]);
          return instanceMirror.invoke(curSym, args).reflectee;
        });
      }
    }
  }
  return _undefined_;
}

getter(self, locals, path) {
  if (self == null) {
    return null;
  }

  List<String> pathKeys = path.split('.');
  var pathKeysLength = pathKeys.length;
  var value = _undefined_;

  if (pathKeysLength == 0) { return self; }

  var currentValue = self;
  for (var i = 0; i < pathKeysLength; i++) {
    var curKey = pathKeys[i];
    if (locals == null) {
      currentValue = _getterChild(currentValue, curKey);
    } else {
      currentValue = _getterChild(locals, curKey);
      locals = null;
      if (currentValue == _undefined_) {
        currentValue = _getterChild(self, curKey);
      }
    }
    if (currentValue == null || currentValue == _undefined_) { return null; }
  }
  return currentValue;
}

_setterChild(obj, childKey, value) {
  // TODO: replace with isInterface(value, Setter) when dart:mirrors
  // can support mixins.
  try {
    return obj[childKey] = value;
  } on NoSuchMethodError catch(e) {}

  InstanceMirror instanceMirror = reflect(obj);
  Symbol curSym = new Symbol(childKey);
  // maybe it is a member field?
  return instanceMirror.setField(curSym, value).reflectee;
}

setter(obj, path, setValue) {
  var element = path.split('.');
  for (var i = 0; element.length > 1; i++) {
    var key = element.removeAt(0);
    var propertyObj = _getterChild(obj, key);
    if (propertyObj == null || propertyObj == _undefined_) {
      propertyObj = {};
      _setterChild(obj, key, propertyObj);
    }
    obj = propertyObj;
  }
  return _setterChild(obj, element.removeAt(0), setValue);
}

class Parser {
  static Profiler _perf;

  Parser(Profiler _perf) {
    // TODO(pavelgj): This is extremely ugly way, but it works for now.
    // Parser needs to be refactored so we don't have to do this.
    Parser._perf = _perf;
  }

  static List<Token> lex(String text) {
    List<Token> tokens = [];
    Token token;
    int index = 0;
    int lastIndex;
    int textLength = text.length;
    String ch;
    String lastCh = ":";

    isIn(String charSet, [String c]) =>  charSet.indexOf(c != null ? c : ch) != -1;
    was(String charSet) => charSet.indexOf(lastCh) != -1;

    cc(String s) => s.codeUnitAt(0);

    bool isNumber([String c]) {
      int cch = cc(c != null ? c : ch);
      return cc('0') <= cch && cch <= cc('9');
    }

    isIdent() {
      int cch = cc(ch);
      return
        cc('a') <= cch && cch <= cc('z') ||
        cc('A') <= cch && cch <= cc('Z') ||
        cc('_') == cch || cch == cc('\$');
    }

    isWhitespace([String c]) => isIn(WHITESPACE, c);

    isExpOperator([String c]) => isIn(SIGN_OP, c) || isNumber(c);

    String peek() => index + 1 < textLength ? text[index + 1] : "EOF";

    // whileChars takes two functions: One called for each character
    // and a second, optional function call at the end of the file.
    // If the first function returns false, the the loop stops and endFn
    // is not run.
    whileChars(fn(), [endFn()]) {
      while (index < textLength) {
        ch = text[index];
        int lastIndex = index;
        if (fn() == false) {
	        return;
	      }
        if (lastIndex >= index) {
	        throw "while chars loop must advance at index $index";
	      }
      }
      if (endFn != null) { endFn(); }
    }

    readString() {
      int start = index;

      String string = "";
      String rawString = ch;
      String quote = ch;

      index++;

      whileChars(() {
        rawString += ch;
        if (ch == '\\') {
          index++;
          whileChars(() {
            rawString += ch;
            if (ch == 'u') {
              String hex = text.substring(index + 1, index + 5);
              int charCode = int.parse(hex, radix: 16,
                  onError: (s) { throw "Lexer Error: Invalid unicode escape [\\u$hex] at column $index in expression [$text]."; });
              string += new String.fromCharCode(charCode);
              index += 5;
            } else {
              var rep = ESCAPE[ch];
              if (rep != null) {
                string += rep;
              } else {
                string += ch;
              }
              index++;
            }
            return false; // BREAK
          });
        } else if (ch == quote) {
          index++;
          tokens.add(new Token(start, rawString)
              ..withString(string)
              ..withFn0(() => string));
          return false; // BREAK
        } else {
          string += ch;
          index++;
        }
      }, () {
        throw "Unterminated quote starting at $start";
      });
    }

    readNumber() {
      String number = "";
      int start = index;
      bool simpleInt = true;
      whileChars(() {
        if (ch == '.') {
          number += ch;
          simpleInt = false;
        } else if (isNumber()) {
          number += ch;
        } else {
          String peekCh = peek();
          if (isIn(EXP_OP) && isExpOperator(peekCh)) {
            simpleInt = false;
            number += ch;
          } else if (isExpOperator() && peekCh != '' && isNumber(peekCh) && isIn(EXP_OP, number[number.length - 1])) {
            simpleInt = false;
            number += ch;
          } else if (isExpOperator() && (peekCh == '' || !isNumber(peekCh)) &&
              isIn(EXP_OP, number[number.length - 1])) {
            throw "Lexer Error: Invalid exponent at column $index in expression [$text].";
          } else {
            return false; // BREAK
          }
        }
        index++;
      });
      var ret = simpleInt ? int.parse(number) : double.parse(number);
      tokens.add(new Token(start, number)..withFn0(() => ret));
    }

    readIdent() {
      String ident = "";
      int start = index;
      int lastDot = -1, peekIndex = -1;
      String methodName;


      whileChars(() {
        if (ch == '.' || isIdent() || isNumber()) {
          if (ch == '.') {
            lastDot = index;
          }
          ident += ch;
        } else {
          return false; // BREAK
        }
        index++;
      });

      // The identifier had a . in the identifier
      if (lastDot != -1) {
        peekIndex = index;
        while (peekIndex < textLength) {
          String peekChar = text[peekIndex];
          if (peekChar == "(") {
            methodName = ident.substring(lastDot - start + 1);
            ident = ident.substring(0, lastDot - start);
            index = peekIndex;
          }
          if (isWhitespace(peekChar)) {
            peekIndex++;
          } else {
            break;
          }
        }
      }

      var token = new Token(start, ident);




      if (OPERATORS.containsKey(ident)) {
        token.withFn(OPERATORS[ident]);
      } else {
        // TODO(deboer): In the JS version this method is incredibly optimized.
        // We should likely do the same.
        token.withFn((self, locals, a, b) => getter(self, locals, ident),
        (self, value, [unused_locals]) =>
          setter(self, ident, value)
        );
      }

      tokens.add(token);

      if (methodName != null) {
        tokens.add(new Token(lastDot, '.'));
        tokens.add(new Token(lastDot + 1, methodName));
      }
    }

    oneLexLoop() {
      if (isIn(QUOTES)) {
        readString();
      } else if (isNumber() || isIn(DOT) && isNumber(peek())) {
        readNumber();
      } else if (isIdent()) {
        readIdent();
        // TODO(deboer): WTF is this doing?
        if (was(JSON_SEP) && inJsonObject() && hasToken()) {
            throw "not impl json fixup";
//          token = tokens.last;
//          token.json = token.text.indexOf('.') == -1;
        }
      } else if (isIn(SPECIAL)) {
        tokens.add(new Token(index, ch));
        index++;
//        if (isIn(OPEN_JSON)) json.unshift(ch);
//        if (isIn(CLOSE_JSON)) json.shift();
      } else if (isWhitespace()) {
        index++;
      } else {
        // Check for two character operators (e.g. "==")
        String ch2 = ch + peek();
        Operator fn = OPERATORS[ch];
        Operator fn2 = OPERATORS[ch2];

        if (fn2 != null) {
          tokens.add(new Token(index, ch2)..withFn(fn2));
          index += 2;
        } else if (fn != null) {
          tokens.add(new Token(index, ch)..withFn(fn));
          index++;
        } else {
          throw "Unexpected next character $index $ch";
        }
      }
    }

    whileChars(() {
      try {
        oneLexLoop();
      } catch (e, s) {
        throw "index: $index $e\nORIG STACK:\n" + s.toString();
      }
    });
    return tokens;

  }

  Expression call(String text) {
    return Parser.parse(text, _perf);
  }

  static Expression parse(text, [_pref]) {
    List<Token> tokens = Parser.lex(text);
    Token token;

    parserError(String s, [Token t]) {
      if (t == null && !tokens.isEmpty) t = tokens[0];
      String location = t == null ?
          'the end of the expression' :
          'at column ${t.index + 1} in';
      return 'Parser Error: $s $location [$text]';
    }
    evalError(String s, [stack]) => ['Eval Error: $s while evaling [$text]' +
        (stack != null ? '\n\nFROM:\n$stack' : '')];

    Token peekToken() {
      if (tokens.length == 0)
        throw "Unexpected end of expression: " + text;
      return tokens[0];
    }

    Token peek([String e1, String e2, String e3, String e4]) {
      if (tokens.length > 0) {
        Token token = tokens[0];
        String t = token.text;
        if (t==e1 || t==e2 || t==e3 || t==e4 ||
            (e1 == null && e2 == null && e3 == null && e4 == null)) {
          return token;
        }
      }
      return null;
    }

    /**
     * Token savers are synchronous lists that allows Parser functions to
     * access the tokens parsed during some amount of time.  They are useful
     * for printing helpful debugging messages.
     */
    List<List<Token>> tokenSavers = [];
    List<Token> saveTokens() { var n = []; tokenSavers.add(n); return n; }
    stopSavingTokens(x) { if (!tokenSavers.remove(x)) { throw 'bad token saver'; } return x; }
    tokensText(List x) => x.map((x) => x.text).join();

    Token expect([String e1, String e2, String e3, String e4]){
      Token token = peek(e1, e2, e3, e4);
      if (token != null) {
        // TODO json
//        if (json && !token.json) {
//          throwError("is not valid json", token);
//        }
        var consumed = tokens.removeAt(0);
        tokenSavers.forEach((ts) => ts.add(consumed));
        return token;
      }
      return null;
    }

    Expression consume(e1){
      if (expect(e1) == null) {
        throw parserError("Missing expected $e1");
        //throwError("is unexpected, expecting [" + e1 + "]", peek());
      }
    }

    var filterChain = null;
    var functionCall, arrayDeclaration, objectIndex, fieldAccess, object;

    Expression primary() {
      var primary;
      var ts = saveTokens();
      if (expect('(') != null) {
        primary = filterChain();
        consume(')');
      } else if (expect('[') != null) {
        primary = arrayDeclaration();
      } else if (expect('{') != null) {
        primary = object();
      } else {
        Token token = expect();
        primary = token.primaryFn;
        if (primary == null) {
          throw parserError("Internal Angular Error: Unreachable code A.");
        }
      }

      // TODO(deboer): I don't think context applies to Dart..
      var next, context;
      while ((next = expect('(', '[', '.')) != null) {
        if (next.text == '(') {
          primary = functionCall(primary, tokensText(ts.sublist(0, ts.length - 1)));
          context = null;
        } else if (next.text == '[') {
          context = primary;
          primary = objectIndex(primary);
        } else if (next.text == '.') {
          context = primary;
          primary = fieldAccess(primary);
        } else {
          throw parserError("Internal Angular Error: Unreachable code B.");
        }
      }
      stopSavingTokens(ts);
      return primary;
    }

    Expression binaryFn(Expression left, Operator fn, Expression right) =>
      new Expression((self, [locals]) {
        return fn(self, locals, left, right);
      });

    Expression unaryFn(Operator fn, Expression right) =>
      new Expression((self, [locals]) {
        return fn(self, locals, right, null);
      });

    Expression unary() {
      var token;
      if (expect('+') != null) {
        return primary();
      } else if ((token = expect('-')) != null) {
        return binaryFn(ZERO, token.fn, unary());
      } else if ((token = expect('!')) != null) {
        return unaryFn(token.fn, unary());
      } else {
        return primary();
      }
    }

    Expression multiplicative() {
      var left = unary();
      var token;
      while ((token = expect('*','/','%')) != null) {
        left = binaryFn(left, token.fn, unary());
      }
      return left;
    }

    Expression additive() {
      var left = multiplicative();
      var token;
      while ((token = expect('+','-')) != null) {
        left = binaryFn(left, token.fn, multiplicative());
      }
      return left;
    }

    Expression relational() {
      var left = additive();
      var token;
      if ((token = expect('<', '>', '<=', '>=')) != null) {
        left = binaryFn(left, token.fn, relational());
      }
      return left;
    }

    Expression equality() {
      var left = relational();
      var token;
      if ((token = expect('==','!=')) != null) {
        left = binaryFn(left, token.fn, equality());
      }
      return left;
    }

    Expression logicalAND() {
      var left = equality();
      var token;
      if ((token = expect('&&')) != null) {
        left = binaryFn(left, token.fn, logicalAND());
      }
      return left;
    }

    Expression logicalOR() {
      var left = logicalAND();
      var token;
      while(true) {
        if ((token = expect('||')) != null) {
          left = binaryFn(left, token.fn, logicalAND());
        } else {
          return left;
        }
      }
    }

    // =========================
    // =========================

    Expression assignment() {
      var ts = saveTokens();
      var left = logicalOR();
      stopSavingTokens(ts);
      var right;
      var token;
      if ((token = expect('=')) != null) {
        if (!left.assignable) {
          throw parserError('Expression ${tokensText(ts)} is not assignable', token);
        }
        right = logicalOR();
        return new Expression((self, [locals]) {
          try {
            return left.assign(self, right.eval(self, locals), locals);
          } catch (e, s) {
            throw evalError('Caught $e', s);
          }
        });
      } else {
        return left;
      }
    }


    Expression expression() {
      return assignment();
    }

    filterChain = () {
      var left = expression();
      var token;
      while(true) {
        if ((token = expect('|')) != null) {
          //left = binaryFn(left, token.fn, filter());
          throw parserError("Filters are not implemented", token);
        } else {
          return left;
        }
      }
    };

    statements() {
      List<Expression> statements = [];
      while (true) {
        if (tokens.length > 0 && peek('}', ')', ';', ']') == null)
          statements.add(filterChain());
        if (expect(';') == null) {
          return statements.length == 1
              ? statements[0]
              : new Expression((self, [locals]) {
                var value;
                for ( var i = 0; i < statements.length; i++) {
                  var statement = statements[i];
                  if (statement != null)
                    value = statement.eval(self, locals);
                }
                return value;
              });
        }
      }
    }

    functionCall = (fn, fnName) {
      var argsFn = [];
      if (peekToken().text != ')') {
        do {
          argsFn.add(expression());
        } while (expect(',') != null);
      }
      consume(')');
      return new Expression((self, [locals]){
        List args = [];
        for ( var i = 0; i < argsFn.length; i++) {
          args.add(argsFn[i].eval(self, locals));
        }
        var userFn = fn.eval(self, locals);
        if (userFn == null) {
          throw evalError("Undefined function $fnName");
        }
        if (userFn is! Function) {
          throw evalError("$fnName is not a function");
        }
        return relaxFnApply(userFn, args);
      });
    };

    // This is used with json array declaration
    arrayDeclaration = () {
      var elementFns = [];
      if (peekToken().text != ']') {
        do {
          elementFns.add(expression());
        } while (expect(',') != null);
      }
      consume(']');
      return new Expression((self, [locals]){
        var array = [];
        for ( var i = 0; i < elementFns.length; i++) {
          array.add(elementFns[i].eval(self, locals));
        }
        return array;
      });
    };

    objectIndex = (obj) {
      // TODO(deboer): Combine these into a single function.
      getField(o, i) {
        if (o is List) {
          return o[i.toInt()];
        } else if (o is Map) {
          return o[i.toString()]; // toString dangerous?
        }
        throw evalError("Attempted field access on a non-list, non-map");
      }

      setField(o, i, v) {
        if (o is List) {
          int arrayIndex = i.toInt();
          if (o.length <= arrayIndex) { o.length = arrayIndex + 1; }
          o[arrayIndex] = v;
        } else if (o is Map) {
          o[i.toString()] = v; // toString dangerous?
        } else {
          throw evalError("Attempting to set a field on a non-list, non-map");
        }
        return v;
      }

      var indexFn = expression();
      consume(']');
      return new Expression((self, [locals]){
            var i = indexFn.eval(self, locals);
            var o = obj.eval(self, locals),
                v, p;

            if (o == null) throw evalError('Accessing null object');

            v = getField(o, i);

            // TODO futures
            /*
            if (v && v.then) {
              p = v;
              if (!('$$v' in v)) {
                p.$$v = undefined;
                p.then(Expression(val) { p.$$v = val; });
              }
              v = v.$$v;
            } */
            return v;
          }, (self, value, [locals]) =>
            setField(obj.eval(self, locals), indexFn.eval(self, locals), value)
          );

    };

    fieldAccess = (object) {
      var field = expect().text;
      //var getter = getter(field);
      return new Expression(
              (self, [locals]) =>
                  getter(object.eval(self, locals), null, field),
              (self, value, [locals]) =>
                  setter(object.eval(self, locals), field, value));
    };

    object = () {
      var keyValues = [];
      if (peekToken().text != '}') {
        do {
          var token = expect(),
              key = token.string != null ? token.string : token.text;
          consume(":");
          var value = expression();
          keyValues.add({"key":key, "value":value});
        } while (expect(',') != null);
      }
      consume('}');
      return new Expression((self, [locals]){
        var object = {};
        for ( var i = 0; i < keyValues.length; i++) {
          var keyValue = keyValues[i];
          var value = keyValue["value"].eval(self, locals);
          object[keyValue["key"]] = value;
        }
        return object;
      });
    };

    // TODO(deboer): json
    Expression value = statements();

    if (tokens.length != 0) {
      throw parserError("Unconsumed token ${tokens[0].text}");
    }
    if (_perf == null) return value;

    var wrappedGetter = (s, [l]) =>
        _perf.time('angular.parser.getter', () => value.eval(s, l), text);
    var wrappedAssignFn = null;
    if (value.assign != null) {
      wrappedAssignFn = (s, v, [l]) =>
          _perf.time('angular.parser.assign',
              () => value.assign(s, v, l), text);
    }
    return new Expression(wrappedGetter, wrappedAssignFn);
  }

}

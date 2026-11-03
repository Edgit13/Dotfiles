.pragma library

// LauncherCalc — маленький безпечний обчислювач виразів для лаунчера.
// Без eval: рекурсивний спуск, підтримує + − * / % ^, дужки, відсотки,
// функції (sqrt, sin, log…) і константи (pi, e, tau). Повертає
// { ok: true, value: "42", raw: 42 } або { ok: false, error: "..." }.

var CONSTANTS = {
    pi: Math.PI,
    e: Math.E,
    tau: Math.PI * 2,
    phi: (1 + Math.sqrt(5)) / 2
}

var FUNCTIONS = {
    sqrt: Math.sqrt,
    cbrt: Math.cbrt,
    abs: Math.abs,
    round: Math.round,
    floor: Math.floor,
    ceil: Math.ceil,
    sign: Math.sign,
    exp: Math.exp,
    ln: Math.log,
    log: Math.log10,
    log2: Math.log2,
    log10: Math.log10,
    sin: Math.sin,
    cos: Math.cos,
    tan: Math.tan,
    asin: Math.asin,
    acos: Math.acos,
    atan: Math.atan,
    sinh: Math.sinh,
    cosh: Math.cosh,
    tanh: Math.tanh,
    min: Math.min,
    max: Math.max,
    hypot: Math.hypot,
    pow: Math.pow,
    atan2: Math.atan2
}

function looksLikeMath(text) {
    var t = String(text || "").trim()
    if (t.length === 0) return false
    if (!/[0-9]/.test(t)) return false
    if (!/^[0-9a-zA-Z+\-*/%^().,\s]+$/.test(t)) return false
    return true
}

function tokenize(text) {
    var tokens = []
    var i = 0
    while (i < text.length) {
        var ch = text.charAt(i)
        if (/\s/.test(ch)) { i++; continue }
        if (/[0-9.]/.test(ch)) {
            var start = i
            var dots = 0
            while (i < text.length && /[0-9.]/.test(text.charAt(i))) {
                if (text.charAt(i) === ".") dots++
                i++
            }
            var raw = text.slice(start, i)
            if (dots > 1) throw new Error("bad number " + raw)
            tokens.push({ type: "number", value: parseFloat(raw) })
            continue
        }
        if (/[a-zA-Z_]/.test(ch)) {
            var s = i
            while (i < text.length && /[a-zA-Z_0-9]/.test(text.charAt(i))) i++
            tokens.push({ type: "name", value: text.slice(s, i).toLowerCase() })
            continue
        }
        if ("+-*/%^(),".indexOf(ch) >= 0) {
            tokens.push({ type: "op", value: ch })
            i++
            continue
        }
        throw new Error("unexpected " + ch)
    }
    return tokens
}

function Parser(tokens) {
    this.tokens = tokens
    this.pos = 0
}

Parser.prototype.peek = function () {
    return this.pos < this.tokens.length ? this.tokens[this.pos] : null
}

Parser.prototype.take = function (value) {
    var token = this.peek()
    if (!token || token.value !== value) throw new Error("expected " + value)
    this.pos++
    return token
}

Parser.prototype.accept = function (value) {
    var token = this.peek()
    if (token && token.type === "op" && token.value === value) {
        this.pos++
        return true
    }
    return false
}

Parser.prototype.parse = function () {
    var value = this.expression()
    if (this.peek() !== null) throw new Error("unexpected " + this.peek().value)
    return value
}

Parser.prototype.expression = function () {
    var value = this.term()
    while (true) {
        if (this.accept("+")) value += this.term()
        else if (this.accept("-")) value -= this.term()
        else return value
    }
}

Parser.prototype.term = function () {
    var value = this.unary()
    while (true) {
        if (this.accept("*")) value *= this.unary()
        else if (this.accept("/")) {
            var divisor = this.unary()
            if (Math.abs(divisor) < 1e-15) throw new Error("division by zero")
            value /= divisor
        } else if (this.accept("%")) {
            var modulus = this.unary()
            if (Math.abs(modulus) < 1e-15) throw new Error("division by zero")
            value %= modulus
        } else if (this.startsValue(this.peek())) {
            value *= this.unary()      // implicit multiplication: 2pi, 3(4+1)
        } else {
            return value
        }
    }
}

Parser.prototype.startsValue = function (token) {
    if (!token) return false
    if (token.type === "number") return true
    if (token.type === "name") return true
    return token.type === "op" && token.value === "("
}

Parser.prototype.unary = function () {
    if (this.accept("+")) return this.unary()
    if (this.accept("-")) return -this.unary()
    return this.power()
}

Parser.prototype.power = function () {
    var base = this.postfix()
    if (this.accept("^")) return Math.pow(base, this.unary())
    return base
}

Parser.prototype.postfix = function () {
    var value = this.primary()
    while (this.accept("!")) {
        value = factorial(value)
    }
    while (this.peek() && this.peek().type === "op" && this.peek().value === "%") {
        this.pos++
        value /= 100
    }
    return value
}

Parser.prototype.primary = function () {
    var token = this.peek()
    if (!token) throw new Error("unexpected end")

    if (token.type === "number") {
        this.pos++
        return token.value
    }

    if (token.type === "name") {
        this.pos++
        var name = token.value
        if (Object.prototype.hasOwnProperty.call(CONSTANTS, name)) {
            if (this.peek() && this.peek().type === "op" && this.peek().value === "(")
                throw new Error("unexpected (")
            return CONSTANTS[name]
        }
        if (Object.prototype.hasOwnProperty.call(FUNCTIONS, name)) {
            this.take("(")
            var args = []
            if (!this.accept(")")) {
                args.push(this.expression())
                while (this.accept(",")) args.push(this.expression())
                this.take(")")
            }
            return FUNCTIONS[name].apply(Math, args)
        }
        throw new Error("unknown " + name)
    }

    if (token.type === "op" && token.value === "(") {
        this.pos++
        var inner = this.expression()
        this.take(")")
        return inner
    }

    throw new Error("unexpected " + token.value)
}

function factorial(value) {
    if (value < 0 || Math.abs(value - Math.round(value)) > 1e-9) throw new Error("factorial needs a whole number")
    if (value > 170) throw new Error("number too large")
    var result = 1
    for (var i = 2; i <= value; i++) result *= i
    return result
}

function formatValue(value) {
    if (!isFinite(value)) return ""
    if (value !== 0 && (Math.abs(value) >= 1e15 || Math.abs(value) < 1e-9))
        return value.toExponential(6).replace(/\.?0+e/, "e")
    var rounded = Math.round(value * 1e10) / 1e10
    return String(rounded)
}

function evaluate(expression) {
    var text = String(expression || "").trim()
    if (text.length === 0) return { ok: false, error: "empty" }
    try {
        var parser = new Parser(tokenize(text))
        var value = parser.parse()
        if (typeof value !== "number" || !isFinite(value))
            return { ok: false, error: "not a finite number" }
        var pretty = formatValue(value)
        if (pretty.length === 0) return { ok: false, error: "not a finite number" }
        return { ok: true, value: pretty, raw: value }
    } catch (error) {
        return { ok: false, error: String(error.message || error) }
    }
}

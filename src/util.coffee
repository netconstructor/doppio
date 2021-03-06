
# pull in external modules
_ = require '../third_party/_.js'
gLong = require '../third_party/gLong.js'

# things assigned to root will be available outside this module
root = exports ? window.util ?= {}

root.INT_MAX = Math.pow(2, 31) - 1
root.INT_MIN = -root.INT_MAX - 1 # -2^31

root.FLOAT_POS_INFINITY = Math.pow(2,128)
root.FLOAT_NEG_INFINITY = -1*root.FLOAT_POS_INFINITY

# sign-preserving number truncate, with overflow and such
root.truncate = (a, n_bits) ->
  max_val = Math.pow 2, n_bits
  a = (a + max_val) % max_val
  a -= max_val if a > Math.pow(2, n_bits-1)
  a

root.wrap_int = (a) -> 
  if a > root.INT_MAX
    root.INT_MIN + (a - root.INT_MAX) - 1
  else if a < root.INT_MIN
    root.INT_MAX - (root.INT_MIN - a) + 1
  else
    a

towards_zero = (a) ->
  Math[if a > 0 then 'floor' else 'ceil'](a)

root.int_mod = (rs, a, b) ->
  root.java_throw rs, 'java/lang/ArithmeticException', '/ by zero' if b == 0
  a % b

root.int_div = (rs, a, b) ->
  root.java_throw rs, 'java/lang/ArithmeticException', '/ by zero' if b == 0
  towards_zero a / b
  # TODO spec: "if the dividend is the negative integer of largest possible magnitude
  # for the int type, and the divisor is -1, then overflow occurs, and the
  # result is equal to the dividend."

root.long_mod = (rs, a, b) ->
  root.java_throw rs, 'java/lang/ArithmeticException', '/ by zero' if b.isZero()
  a.modulo(b)

root.long_div = (rs, a, b) ->
  root.java_throw rs, 'java/lang/ArithmeticException', '/ by zero' if b.isZero()
  a.div(b)

root.float2int = (a) ->
  if a == NaN then 0
  else if a > root.INT_MAX then root.INT_MAX  # these two cases handle d2i issues
  else if a < root.INT_MIN then root.INT_MIN
  else unless a == Infinity or a == -Infinity then towards_zero a
  else if a > 0 then root.INT_MAX
  else root.INT_MIN

root.wrap_float = (a) ->
  return Infinity if a > 3.40282346638528860e+38
  return 0 if 0 < a < 1.40129846432481707e-45
  return -Infinity if a < -3.40282346638528860e+38
  return 0 if 0 > a > -1.40129846432481707e-45
  a

root.cmp = (a,b) ->
  return 0  if a == b
  return -1 if a < b
  return 1  if a > b
  return null # this will occur if either a or b is NaN

# implements x<<n without the braindead javascript << operator
# (see http://stackoverflow.com/questions/337355/javascript-bitwise-shift-of-long-long-number)
root.lshift = (x,n) -> x*Math.pow(2,n)

root.read_uint = (bytes) ->
  n = bytes.length-1
  # sum up the byte values shifted left to the right alignment.
  sum = 0
  for i in [0..n] by 1
    sum += root.lshift(bytes[i],8*(n-i))
  sum

root.uint2int = (uint, bytes_count) ->
  n_bits = 8 * bytes_count
  if uint > Math.pow(2, n_bits - 1)
    uint - Math.pow(2, n_bits)
  else
    uint

root.int2uint = (int, bytes_count) ->
  if int < 0 then int + Math.pow 2, bytes_count * 8 else int

root.bytestr_to_array = (bytecode_string) ->
  (bytecode_string.charCodeAt(i) & 0xFF for i in [0...bytecode_string.length] by 1)

root.parse_flags = (flag_byte) -> {
    public:       flag_byte & 0x1
    private:      flag_byte & 0x2
    protected:    flag_byte & 0x4
    static:       flag_byte & 0x8
    final:        flag_byte & 0x10
    synchronized: flag_byte & 0x20
    super:        flag_byte & 0x20
    volatile:     flag_byte & 0x40
    transient:    flag_byte & 0x80
    native:       flag_byte & 0x100
    interface:    flag_byte & 0x200
    abstract:     flag_byte & 0x400
    strict:       flag_byte & 0x800
  }

class root.BytesArray
  constructor: (@raw_array, @start=0, @end=@raw_array.length) ->
    @_index = 0

  pos: -> @_index

  skip: (bytes_count) -> @_index += bytes_count

  has_bytes: -> @start + @_index < @end

  get_uint: (bytes_count) ->
    rv = root.read_uint @raw_array.slice(@start + @_index, @start + @_index + bytes_count)
    @_index += bytes_count
    return rv

  get_int: (bytes_count) ->
    root.uint2int @get_uint(bytes_count), bytes_count

  read: (bytes_count) ->
    rv = @raw_array[@start+@_index...@start+@_index+bytes_count]
    @_index += bytes_count
    rv

  peek: -> @raw_array[@start+@_index]

  size: -> @end - @start - @_index

  splice: (len) ->
    arr = new root.BytesArray @raw_array, @start+@_index, @start+@_index+len
    @_index += len
    arr

root.initial_value = (type_str) ->
  if type_str is 'J' then gLong.ZERO
  else if type_str[0] in ['[','L'] then null
  else 0

root.is_string = (obj) -> typeof obj == 'string' or obj instanceof String

# Walks up the prototype chain of :object looking for an entry in the :handlers
# dict that match its constructor's name.
root.lookup_handler = (handlers, object) ->
  obj = object
  while obj?
    handler = handlers[obj.constructor.name]
    return handler if handler
    obj = Object.getPrototypeOf obj
  return null

# Runs root.lookup_handler, and if it finds one, it calls that handler
# with :object bound to `this` and :args as the arguments.
root.call_handler = (handlers, object, args...) ->
  root.lookup_handler(handlers,object)?.apply object, args

class root.BranchException
  constructor: (@dst_pc) ->

class root.HaltException
  constructor: (@exit_code) ->

class root.ReturnException
  constructor: (@values...) ->

class root.YieldException
  constructor: (@condition) ->

class root.YieldIOException
  constructor: (@condition) ->

class root.JavaException
  constructor: (rs, @exception) ->

# Simulate the throwing of a Java exception with message :msg. Not very DRY --
# code here is essentially copied from the opcodes themselves -- but
# constructing the opcodes manually is inelegant too.
root.java_throw = (rs, cls, msg) ->
  method_spec = class: cls, sig: '<init>(Ljava/lang/String;)V'
  v = rs.init_object cls # new
  rs.push(v,v,rs.init_string msg) # dup, ldc
  rs.method_lookup(method_spec).run(rs) # invokespecial
  throw new root.JavaException rs, rs.pop() # athrow

# logging helpers
root.VTRACE = 10
root.TRACE = 9
root.DEBUG = 5
root.ERROR = 1
root.log_level ?= root.ERROR

root.log = (level, msgs...) ->
  if level <= root.log_level
    console[if level == 1 then 'error' else 'log'] msgs...

root.vtrace = (msgs...) -> root.log root.VTRACE, msgs...
root.trace = (msgs...) -> root.log root.TRACE, msgs...
root.debug = (msgs...) -> root.log root.DEBUG, msgs...
root.error = (msgs...) -> root.log root.ERROR, msgs...

# Java classes are represented internally using slashes as delimiters.
# These helper functions convert between the two representations.
root.ext_classname = (str) -> str.replace /\//g, '.'
root.int_classname = (str) -> str.replace /\./g, '/'

# Parse Java's pseudo-UTF-8 strings. (spec 4.4.7)
root.bytes2str = (bytes) ->
  idx = 0
  char_array =
    while idx < bytes.length
      x = root.int2uint bytes[idx++], 1
      break if x == 0
      String.fromCharCode(
        if x <= 0x7f
          x
        else if x <= 0xdf
          y = bytes[idx++]
          ((x & 0x1f) << 6) + (y & 0x3f)
        else
          y = bytes[idx++]
          z = bytes[idx++]
          ((x & 0xf) << 12) + ((y & 0x3f) << 6) + (z & 0x3f)
      )
  char_array.join ''

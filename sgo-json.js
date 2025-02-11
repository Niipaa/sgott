const SIZE = 12
const sgoMeta = require('./sgo-meta')

// Cheapo(tm) debugging
function abort() {
  throw new Error('abort')
}

function decompiler(config = {}) {
  var endian
  const types = {
    0: ['ptr', Int, Pointer],
    1: ['int', Int],
    2: ['float', Float],
    3: ['string', Int, StrPointer],
    4: ['extra', Int, ExtraPointer],
  }

  function Str(buffer) {
    return (endian === 'LE'
      ? buffer.toString('utf16le')
      : Buffer.from(buffer).swap16().toString('utf16le')
    ).trim()
  }

  function UInt(buffer, offset = 0) {
    return buffer[`readUInt32${endian}`](offset)
  }

  function Int(buffer, offset = 0) {
    return buffer[`readInt32${endian}`](offset)
  }

  function Float(buffer, offset = 0) {
    return buffer[`readFloat${endian}`](offset)
  }

  function Pointer(buffer, index, size) {
    if(!size) return null
    return consume(buffer, index, size)
  }

  function StrPointer(buffer, index, size) {
    const end = index + size * 2 || buffer.length
    const terminator = Math.min(buffer.indexOf('\0', index, 'utf16le'), end)
    return Str(buffer.slice(index, terminator > 0 ? terminator : end))
  }

  function ExtraPointer(buffer, index, size) {
    const leader = buffer.slice(index, index + 4).toString()
    const data = buffer.slice(index, index + size)
    if(['SGO\0', '\0OGS'].includes(leader)) {
      return {
        type: 'SGO',
        data: decompiler({offset: ((config && config.offset) || 0) + index})(data),
      }
    } else {
      return {
        type: leader.trim(),
        data: data.toString('base64'),
      }
    }
    return buffer.slice(index, index + size).toString('base64')
  }

  function chomp(data, index, opts = {}) {
    const [type, transform, getPointed] = types[UInt(data, index)] || []
    if(!type) {
      return {
        type: 'unknown',
        value: data.slice(index, index + SIZE).toString('base64'),
      }
    }
    const isPointer = ['ptr', 'string', 'extra'].includes(type)
    const size = UInt(data, index + 4)
    const value = transform(data, index + 8)
    const pointed = !opts.shallow && getPointed && getPointed(data, index + value, size)
    const payload = {type}

    if(config.debug) {
      const pos = index + ((config && config.offset) || 0)
      payload.index = pos.toString(16)
      if(isPointer) {
        payload.relative = value.toString(16)
        payload.pointer = (pos + value).toString(16)
        payload.size = size
      }
    }

    payload.value = isPointer ? pointed : pointed || value

    return payload
  }

  function consume(data, index, values, opts) {
    const ret = new Array(values)
    for(var i = 0; i < values; i++) {
      ret[i] = chomp(data, index + i * SIZE, opts)
    }
    return ret
  }

  function readHeader(buffer) {
    // Header of SGO file is 32 bytes, this is the structure as I know it:
    //
    // HHHH HHHH 0000 0102 CCCC CCCC 0000 0020
    // CCCC CCCC MMMM MMMM 0000 0000 SSSS SSSS
    //
    // Note that 0102 and 0020 will be 0201 and 2000 in little-endian
    // 8 distinct values, each 4 bytes

    // H is the leader describing the file type
    // It can be one of two strings:
    //  Little endian: "SGO\0"
    //  Big Endian:    "\0OGS"
    const leader = buffer.slice(0, 4).toString()
    endian = leader === 'SGO\0' ? 'LE' : 'BE'
    
    // C is count of variables (not including values in pointed structs)
    // It appears twice for reasons unknown
    const varCount = UInt(buffer, 8)

    // M is a pointer to an array of tuples (*varname, index)
    const mIndex = UInt(buffer, 20)

    // S is a pointer to the end of the struct, right after mbuffer ends
    // We have no particular use for it
    const structEnd = 4 + Int(buffer, 28)

    return {leader, varCount, mIndex, structEnd}
  }

  var ammoClass, summonType
  function addNames(parent) {
    if(!parent.value) return
    const nodes = parent.value
    const {name} = parent
    if(name === 'SummonType') summonType = nodes
    const names
      = name === 'Ammo_CustomParameter'
        ? sgoMeta.names.ammoClasses[ammoClass]
      :  name === 'Summon_CustomParameter'
        ? sgoMeta.names.ammoClasses['Summon_CustomParameter0' + summonType]
        : sgoMeta.names[name]
    if(!names) return
    for(var i = 0; i < nodes.length; i++) {
      const name = names[i]
      if(!name) continue
      const node = nodes[i]
      node.name = name
      addNames(node)
      addMetaData(node)
    }
  }

  function addMetaData(node) {
    const {name, value} = node
    if(!name) return

    const options = sgoMeta.values[name]
    if(options) node.options = options

    // Reorder value so it's listed below name
    delete node.value
    node.value = value
  }

  return {
    decompile(buffer) {
      const {mIndex, varCount} = readHeader(buffer)

      // Read C variables from he fixed section, then assign names using the mTable
      const variables = consume(buffer, 32, varCount)
      for(let i = 0; i < varCount; i++) {
        const index = mIndex + i * 8
        const strIndex = Int(buffer, index)
        const varIndex = UInt(buffer, index + 4)
        const name = StrPointer(buffer, index + strIndex)
        const node = variables[varIndex]
        node.name = name

        if(name === 'AmmoClass') ammoClass = node.value
        addNames(node)
        addMetaData(node)
      }

      return {endian, variables}
    },
    dumpvalues(buffer) {
      const {mIndex} = readHeader(buffer)

      return consume(buffer, 32, Math.ceil(mIndex - 32 / 12), {shallow: true})
    }
  }[config.mode || 'decompile']
}

function decompile(buffer, opts = {}) {
  const data = decompiler(opts)(buffer.slice(opts.offset || 0))
  data.meta = {
    help: 'For examples of these values, open WEAPONTABLE.SGO and WEAPONTEXT.SGO',
    id: null,
    level: null,
    category: null,
    unlockState: null,
    dropRateModifier: null,
    description: null,
  }

  return JSON.stringify(data, null, 2)
}

decompile.decompiler = decompiler

module.exports = decompile

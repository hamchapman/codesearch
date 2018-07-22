import Foundation

// Constants
let indexHeader = "csearch index 1\n"
let indexTrailer = "\ncsearch trailr\n"
let postEntrySize = 3 + 4 + 4

//// An mmapData is mmap'ed read-only data from a file.
//
////type mmapData struct {
////    f *os.File
////    d []byte
////}
//
struct MmapData {
    let filePath: URL
    let data: Data
}


// An Index implements read-only access to a trigram index.
struct Index {
    let verbose: Bool
    let data: MmapData
    let pathData: UInt32
    let nameData: UInt32
    let postData: UInt32
    let nameIndex: UInt32
    let postIndex: UInt32
    let numName: Int
    let numPost: Int
}

func corrupt() {
    fatalError("Corrupt index: remove \(indexPath())")
}

// mmap maps the given file into memory.
func mmap(filePath: String) -> MmapData {
//    f, err := os.Open(file)
//    if err != nil {
//        log.Fatal(err)
//    }

    guard let filePathURL = URL(string: filePath) else {
        fatalError("Couldn't create URL from string: \(filePath)")
    }

    return mmapFile(filePath: filePathURL)
}


func openIndex(atFilePath filePath: String) -> Index {
    let mm = mmap(filePath: filePath)
    let indexTrailerBytesLength = indexTrailer.lengthOfBytes(using: .utf8)
    let afterTrailerOffset = mm.data.count - indexTrailer.count

    // TODO: Is lengthOfBytes correct? Is utf8 correct?
    guard mm.data.count >= 4 * 4 + indexTrailerBytesLength else {
        corrupt()
    }

    // TODO: Should the range be ..< or ...
    guard String(data: mm.data.subdata(in: afterTrailerOffset..<mm.data.endIndex), encoding: .utf8) != indexTrailer else {
        corrupt()
    }

    let n = UInt32(mm.data.count - indexTrailerBytesLength - 5 * 4)

    let index = Index(
        verbose: false,
        data: mm,
        pathData: UInt32(n),
        nameData: UInt32(n + 4),
        postData: UInt32(n + 8),
        nameIndex: UInt32(n + 12),
        postIndex: UInt32(n + 16),
        numName: Int((UInt32(n + 16) - UInt32(n + 12)) / 4) - 1,
        numPost: Int((n - (n + 16))) / postEntrySize
    )

    return index

//    ix := &Index{data: mm}
//    ix.pathData = ix.uint32(n)
//    ix.nameData = ix.uint32(n + 4)
//    ix.postData = ix.uint32(n + 8)
//    ix.nameIndex = ix.uint32(n + 12)
//    ix.postIndex = ix.uint32(n + 16)
//    ix.numName = int((ix.postIndex-ix.nameIndex)/4) - 1
//    ix.numPost = int((n - ix.postIndex) / postEntrySize)
//    return ix
}

// TODO: Does slice work with length -1 (e.g. from IndexByte)
// slice returns the slice of index data starting at the given byte offset.
// If length >= 0, the slice must have length at least length and is truncated
// to length length.
func slice(index: Index, offset: UInt32, length: Int) -> Data {
    let o = Int(offset)

    if UInt32(o) != offset || length >= 0 && o + length > index.data.data.count {
        corrupt()
    }

    if length < 0 {
        return index.data.data[o..<index.data.data.endIndex]
    }

    return index.data.data[o..<(o + length)]
}

///// Gets an unsigned int (32 bits => 4 bytes) from the given index.
/////
///// - parameter index: The index of the uint to be retrieved. Note that this should never be >= length -
/////                    3.
/////
///// - returns: The unsigned int located at position `index`.
//func getUnsignedInteger(at index: Int, bigEndian: Bool = true) -> UInt32 {
//    let data: UInt32 =  self.subdata(in: index ..< (index + 4)).withUnsafeBytes { $0.pointee }
//    return bigEndian ? data.bigEndian : data.littleEndian
//}

// uint32 returns the uint32 value at the given offset in the index data.
func valueOf(index: Index, atOffset offset: UInt32) -> UInt32 {
    let data: UInt32 = slice(index: index, offset: offset, length: 4).withUnsafeBytes { $0.pointee }
    return data.bigEndian
}

func uvarint(index: Index, offset: UInt32) -> UInt32 {
//    v, n := binary.Uvarint(ix.slice(off, -1))
//    if n <= 0 {
//        corrupt()
//    }
//    return uint32(v)
//
//
//    v, n := binary.Uvarint(ix.slice(off, -1))

    let data: UInt32 = slice(index: index, offset: offset, length: -1).withUnsafeBytes { $0.pointee }
    return data
}


// Paths returns the list of indexed paths.
//func (ix *Index) Paths() []string {
//    off := ix.pathData
//    var x []string
//    for {
//        s := ix.str(off)
//        if len(s) == 0 {
//            break
//        }
//        x = append(x, string(s))
//        off += uint32(len(s) + 1)
//    }
//    return x
//}

func paths(fromIndex index: Index) -> [String] {
    var offset = index.pathData
    var paths: [String] = []

    for {
        let s = str(index: index, offset: offset)
        if s.count == 0 {
            break
        }
        paths.append(String(data: s, encoding: .utf8))
        offset = offset + UInt32(s.count + 1)
    }

    return paths
}


func str(index: Index, offset: UInt32) -> Data {
    let str = slice(index: index, offset: offset, length: -1)
    guard let i = str.firstIndex(where: { $0 == 0x0 }) else { // TODO: does this check work or do I need to do String($0) == "\0"
        corrupt()
    }

    return str[str.startIndex..<i]
}


// NameBytes returns the name corresponding to the given fileid.
func nameBytes(index: Index, fileID: UInt32) -> Data {
    let offset = index.nameIndex + (4 * fileID)
    return str(index: index, offset: index.nameData + offset)
}

func name(index: Index, fileID: UInt32) -> String {
    // TODO: Should we bang here?
    return String(data: nameBytes(index: index, fileID: fileID), encoding: .utf8)!
}

// TODO: This seems a bit mad
// TODO: Probs want to make a struct for the list
func listAt(index: Index, offset: UInt32) -> (trigram: UInt32, count: UInt32, offset: UInt32) {
    let d = slice(index: index, offset: index.postIndex + offset, length: postEntrySize)
    let trigram = UInt32(d[0]) << 16 | UInt32(d[1]) << 8 | UInt32(d[2])
    let countData: UInt32 = d[3..<d.endIndex].withUnsafeBytes { $0.pointee }
    let count = countData.bigEndian
    let returnOffsetData: UInt32 = d[(3 + 4)..<d.endIndex].withUnsafeBytes { $0.pointee }
    let offsetToReturn = returnOffsetData.bigEndian
    return (trigram, count, offsetToReturn)
}

func dumpPosting(index: Index) {
    let d = slice(index: index, offset: index.postIndex, length: postEntrySize * index.numPost)

    (0...index.numPost).forEach { i in
        let j = i * postEntrySize
        let t = UInt32(d[j]) << 16 | UInt32(d[j+1]) << 8 | UInt32(d[j + 2])
        let countData: UInt32 = d[(j + 3)..<d.endIndex].withUnsafeBytes { $0.pointee }
        let count = countData.bigEndian
        let offsetData: UInt32 = d[(j + 3 + 4)..<d.endIndex].withUnsafeBytes { $0.pointee }
        let offset = offsetData.bigEndian

//        log.Printf("%#x: %d at %d", t, count, offset)
        print("Dump: ", t, count, offset)
    }
}

func findList(index: Index, trigram: UInt32) -> (count: Int, offset: UInt32) {
    // binary search
    let d = slice(index: index, offset: index.postIndex, length: postEntrySize * index.numPost)

    var i = sort.Search(index.numPost, { (i: Int) -> Bool in
        i *= postEntrySize
        let t = UInt32(d[i]) << 16 | UInt32(d[i + 1]) << 8 | UInt32(d[i + 2])
        return t >= trigram
    })

    guard i < index.numPost else {
        return (0, 0)
    }

    i *= postEntrySize
    let t = UInt32(d[i]) << 16 | UInt32(d[i + 1]) << 8 | UInt32(d[i + 2])

    guard t == trigram else {
        return (0, 0)
    }

    let countData: UInt32 = d[(i + 3)..<d.endIndex].withUnsafeBytes { $0.pointee }
    let count = countData.bigEndian
    let offsetData: UInt32 = d[(i + 3 + 4)..<d.endIndex].withUnsafeBytes { $0.pointee }
    let offset = offsetData.bigEndian

    return (count, offset)
}


//func (ix *Index) str(off uint32) []byte {
//    str := ix.slice(off, -1)
//    i := bytes.IndexByte(str, '\x00')
//    if i < 0 {
//        corrupt()
//    }
//    return str[:i]
//}

// Name returns the name corresponding to the given fileid.
//func (ix *Index) Name(fileid uint32) string {
//    return string(ix.NameBytes(fileid))
//}

// listAt returns the index list entry at the given offset.
//func (ix *Index) listAt(off uint32) (trigram, count, offset uint32) {
//    d := ix.slice(ix.postIndex+off, postEntrySize)
//    trigram = uint32(d[0])<<16 | uint32(d[1])<<8 | uint32(d[2])
//    count = binary.BigEndian.Uint32(d[3:])
//    offset = binary.BigEndian.Uint32(d[3+4:])
//    return
//}

//func (ix *Index) dumpPosting() {
//    d := ix.slice(ix.postIndex, postEntrySize*ix.numPost)
//    for i := 0; i < ix.numPost; i++ {
//        j := i * postEntrySize
//        t := uint32(d[j])<<16 | uint32(d[j+1])<<8 | uint32(d[j+2])
//        count := int(binary.BigEndian.Uint32(d[j+3:]))
//        offset := binary.BigEndian.Uint32(d[j+3+4:])
//        log.Printf("%#x: %d at %d", t, count, offset)
//    }
//}

//func (ix *Index) findList(trigram uint32) (count int, offset uint32) {
//    // binary search
//    d := ix.slice(ix.postIndex, postEntrySize*ix.numPost)
//    i := sort.Search(ix.numPost, func(i int) bool {
//    i *= postEntrySize
//    t := uint32(d[i])<<16 | uint32(d[i+1])<<8 | uint32(d[i+2])
//    return t >= trigram
//    })
//    if i >= ix.numPost {
//        return 0, 0
//    }
//    i *= postEntrySize
//    t := uint32(d[i])<<16 | uint32(d[i+1])<<8 | uint32(d[i+2])
//    if t != trigram {
//        return 0, 0
//    }
//    count = int(binary.BigEndian.Uint32(d[i+3:]))
//    offset = binary.BigEndian.Uint32(d[i+3+4:])
//    return
//}



class PostReader {
    let index: Index
    var count: Int
    let offset: UInt32
    var fileID: UInt32
    let data: Data
    var restrict: [UInt32]?

    init(index: Index, trigram: UInt32, restrict: [UInt32]? = nil) {
        let (count, offset) = findList(index: index, trigram: trigram)
        guard count != 0 else {
            return // TOOD: Should this be a failable intializer?
        }
        self.index = index
        self.count = count
        self.offset = offset
        self.fileID = ~UInt32(0)
        self.data = slice(index: index, offset: index.postData + offset + 3, length: -1)
        self.restrict = restrict
    }

    func max() -> Int {
        return self.count
    }

    func next() -> Bool {
        while self.count > 0 {
            self.count -= 1
            let delta: UInt32 = self.data.withUnsafeBytes { $0.pointee }
//            delta64, n := binary.Uvarint(r.d)


            if n <= 0 || delta == 0 {
                corrupt()
            }
            self.data = self.data[n..<self.data.endIndex]
            self.fileID += delta
            if self.restrict != nil {
                var i = 0
                while i < self.restrict!.count && self.restrict![i] < self.fileID {
                    i += 1
                }
                self.restrict! = self.restrict![i..<self.restrict!.endIndex]
                if self.restrict!.count == 0 || self.restrict![0] != self.fileID {
                    continue
                }
            }
            return true
        }
        // list should end with terminating 0 delta
        // TODO: Should data be optional?
        if self.data != nil && (self.data.count == 0 || self.data[0] != 0) {
            corrupt()
        }
        self.fileID = ~UInt32(0)
        return false
    }
}

//func (r *postReader) init(ix *Index, trigram uint32, restrict []uint32) {
//    count, offset := ix.findList(trigram)
//    if count == 0 {
//        return
//    }
//    r.ix = ix
//    r.count = count
//    r.offset = offset
//    r.fileid = ^uint32(0)
//    r.d = ix.slice(ix.postData+offset+3, -1)
//    r.restrict = restrict
//}

//func (r *postReader) max() int {
//    return int(r.count)
//}
//
//func (r *postReader) next() bool {
//    for r.count > 0 {
//        r.count--
//        delta64, n := binary.Uvarint(r.d)
//        delta := uint32(delta64)
//        if n <= 0 || delta == 0 {
//            corrupt()
//        }
//        r.d = r.d[n:]
//        r.fileid += delta
//        if r.restrict != nil {
//            i := 0
//            for i < len(r.restrict) && r.restrict[i] < r.fileid {
//                i++
//            }
//            r.restrict = r.restrict[i:]
//            if len(r.restrict) == 0 || r.restrict[0] != r.fileid {
//                continue
//            }
//        }
//        return true
//    }
//    // list should end with terminating 0 delta
//    if r.d != nil && (len(r.d) == 0 || r.d[0] != 0) {
//        corrupt()
//    }
//    r.fileid = ^uint32(0)
//    return false
//}

//func (ix *Index) PostingList(trigram uint32) []uint32 {
//    return ix.postingList(trigram, nil)
//}

//func postingList(index: Index, trigram: UInt32) -> [UInt32] {
//    return postingList(index: index, trigram: trigram, restrict: nil)
//}

func postingList(index: Index, trigram: UInt32, restrict: [UInt32]? = nil) -> [UInt32] {
    let r = PostReader(index: index, trigram: trigram, restrict: restrict)
    var x: [UInt32] = Array(repeating: 0, count: r.max())
    while r.next() { x.append(r.fileID) }
    return x
}

//func (ix *Index) postingList(trigram uint32, restrict []uint32) []uint32 {
//    var r postReader
//    r.init(ix, trigram, restrict)
//    x := make([]uint32, 0, r.max())
//    for r.next() {
//        x = append(x, r.fileid)
//    }
//    return x
//}

//func (ix *Index) PostingAnd(list []uint32, trigram uint32) []uint32 {
//    return ix.postingAnd(list, trigram, nil)
//}

//func postingAnd(index: Index, list: [UInt32], trigram: UInt32) -> [UInt32] {
//    return postingAnd(list, trigram, nil)
//}

func postingAnd(index: Index, list: [UInt32], trigram: UInt32, restrict: [UInt32]? = nil) -> [UInt32] {
    let r = PostReader(index: index, trigram: trigram, restrict: restrict)
    var x = list[:0] // TOOD: wut?
    var i = 0
    while r.next() {
        let fileID = r.fileID
        while i < list.count && list[i] < fileID {
            i += 1
        }
        if i < list.count && list[i] == fileID {
            x.append(fileID)
            i += 1
        }
    }
    return x
}

//func (ix *Index) PostingOr(list []uint32, trigram uint32) []uint32 {
//    return ix.postingOr(list, trigram, nil)
//}

func postingOr(index: Index, list: [UInt32], trigram: UInt32, restrict: [UInt32]? = nil) -> [UInt32] {
    let r = PostReader(index: index, trigram: trigram, restrict: restrict)
    var x: [UInt32] = Array(repeating: 0, count: list.count + r.max())
    var i = 0
    while r.next() {
        let fileID = r.fileID
        while i < list.count && list[i] < fileID {
            x.append(list[i])
            i += 1
        }
        x.append(fileID)
        if i < list.count && list[i] == fileID {
            i += 1
        }
    }
    x.append(contentsOf: list[i..<list.endIndex])
    return x
}

func postingQuery(index: Index, query: Query, restrict: [UInt32]? = nil) -> [UInt32] {
    var list: [UInt32] = []
    switch q.Op {
    case QNone:
    // nothing
    case QAll:
        if restrict != nil {
            return restrict
        }
        list = make([]uint32, ix.numName)
        for i := range list {
            list[i] = uint32(i)
        }
        return list
    case QAnd:
        for _, t := range q.Trigram {
            tri := uint32(t[0])<<16 | uint32(t[1])<<8 | uint32(t[2])
            if list == nil {
                list = ix.postingList(tri, restrict)
            } else {
                list = ix.postingAnd(list, tri, restrict)
            }
            if len(list) == 0 {
                return nil
            }
        }
        for _, sub := range q.Sub {
            if list == nil {
                list = restrict
            }
            list = ix.postingQuery(sub, list)
            if len(list) == 0 {
                return nil
            }
        }
    case QOr:
        for _, t := range q.Trigram {
            tri := uint32(t[0])<<16 | uint32(t[1])<<8 | uint32(t[2])
            if list == nil {
                list = ix.postingList(tri, restrict)
            } else {
                list = ix.postingOr(list, tri, restrict)
            }
        }
        for _, sub := range q.Sub {
            list1 := ix.postingQuery(sub, restrict)
            list = mergeOr(list, list1)
        }
    }
    return list
}


//func (ix *Index) PostingQuery(q *Query) []uint32 {
//    return ix.postingQuery(q, nil)
//}

//func (ix *Index) postingQuery(q *Query, restrict []uint32) (ret []uint32) {
//    var list []uint32
//    switch q.Op {
//    case QNone:
//    // nothing
//    case QAll:
//        if restrict != nil {
//            return restrict
//        }
//        list = make([]uint32, ix.numName)
//        for i := range list {
//            list[i] = uint32(i)
//        }
//        return list
//    case QAnd:
//        for _, t := range q.Trigram {
//            tri := uint32(t[0])<<16 | uint32(t[1])<<8 | uint32(t[2])
//            if list == nil {
//                list = ix.postingList(tri, restrict)
//            } else {
//                list = ix.postingAnd(list, tri, restrict)
//            }
//            if len(list) == 0 {
//                return nil
//            }
//        }
//        for _, sub := range q.Sub {
//            if list == nil {
//                list = restrict
//            }
//            list = ix.postingQuery(sub, list)
//            if len(list) == 0 {
//                return nil
//            }
//        }
//    case QOr:
//        for _, t := range q.Trigram {
//            tri := uint32(t[0])<<16 | uint32(t[1])<<8 | uint32(t[2])
//            if list == nil {
//                list = ix.postingList(tri, restrict)
//            } else {
//                list = ix.postingOr(list, tri, restrict)
//            }
//        }
//        for _, sub := range q.Sub {
//            list1 := ix.postingQuery(sub, restrict)
//            list = mergeOr(list, list1)
//        }
//    }
//    return list
//}

func mergeOr(l1: [UInt32], l2: [UInt32]) -> [UInt32] {
    var l: [UInt32] = []
    var i = 0
    var j = 0
    while i < l1.count || j < l2.count {
        switch {
        case j == l2.count || (i < l1.count && l1[i] < l2[j]):
            l.append(l1[i])
            i += 1
        case i == l1.count || (j < l2.count && l1[i] > l2[j]):
            l.append(l2[j])
            j += 1
        case l1[i] == l2[j]:
            l.append(l1[i])
            i += 1
            j += 1
        }
    }
    return l
}



// Returns the name of the index file to use.
// It's either $CSEARCHINDEX or $HOME/.csearchindex.
func indexPath() -> String {
    if let cSearchIndex = ProcessInfo.processInfo.environment["CSEARCHINDEX"] {
        if !cSearchIndex.isEmpty {
            return cSearchIndex
        }
    }

    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".csearchindex").absoluteString
}

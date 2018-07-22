import Foundation

//let floatPtr = rawPtr.bindMemory(to: Float.self, capacity: numFloats)


//const (
//    _PROT_READ  = 1
//    _MAP_SHARED = 1
//)
//
//func mmapFile(f *os.File) mmapData {
//    st, err := f.Stat()
//    if err != nil {
//        log.Fatal(err)
//    }
//    size := st.Size()
//    if int64(int(size+4095)) != size+4095 {
//        log.Fatalf("%s: too large for mmap", f.Name())
//    }
//    n := int(size)
//    if n == 0 {
//        return mmapData{f, nil}
//    }
//    data, err := syscall.Mmap(int(f.Fd()), 0, (n+4095)&^4095, _PROT_READ, _MAP_SHARED)
//    if err != nil {
//        log.Fatalf("mmap %s: %v", f.Name(), err)
//    }
//    return mmapData{f, data[:n]}
//}


func mmapFile(filePath: URL) -> MmapData {
//    let fileName = filePath.lastPathComponent

    guard let fullPathName = filePath.absoluteString.cString(using: .utf8) else {
        fatalError("Couldn't get cString from file path")
    }

    let fd = open(fullPathName, O_RDONLY, 0)

    defer {
        close(fd)
    }

    if fd < 0 {
        fatalError("fd value less than 0")
    }

    var buf = stat()

    if fstat(fd, &buf) != 0 {
        fatalError("fstat returned non-zero return value")
    }

    // do stuff and then close

    // TODO: Is this the best / correct way of getting the size?
    let size = buf.st_size

    guard size != 0 else {
        return MmapData(filePath: filePath, data: Data())
    }

    mmap(<#T##UnsafeMutableRawPointer!#>, <#T##Int#>, <#T##Int32#>, <#T##Int32#>, <#T##Int32#>, <#T##off_t#>)

    ////////////////////////////////////

//    guard let mptr = mmap(nil, Int(getpagesize()), PROT_READ, MAP_SHARED, -1, 0) else {
//        fatalError("mmap failed")
//    }
//
//    if (Int(bitPattern: mptr) == -1) { // MAP_FAILED not available, but its value is (void*)-1
//        fatalError("mmap error")
//    }
//
//    guard let fileAttributes = attributes(ofFile: filePath) else {
//        fatalError("Couldn't get file attributes")
//    }
//
//    let fileSize = fileAttributes[.size] as? UInt64 ?? UInt64(0)
//
//    guard fileSize != 0 else {
//        return MmapData(filePath: filePath, data: Data())
//    }
}

func attributes(ofFile file: URL) -> [FileAttributeKey: Any]? {
    do {
        return try FileManager.default.attributesOfItem(atPath: file.path)
    } catch let error as NSError {
        print("FileAttribute error: \(error)")
    }
    return nil
}


import Foundation

extension String {
    subscript (i: Int) -> Character {
        return self[index(startIndex, offsetBy: i)]
    }
}

// StringSet should probably be a protocol which Array<String> could
// then conform to. Likewise, Set<String> could proablby conform, as
// could things like SortedArray<String>. For now having it as a
// concrete type is probably fine.

// A StringSet is a set of strings.
// The nil StringSet indicates not having a set.
// The non-nil but empty StringSet is the empty set.
class StringSet {
    var stringSet: Array<String>?

    init(_ set: Array<String>? = nil) {
        self.stringSet = set
    }

    // contains reports whether a StringSet contains str.
    func contains(str: String) -> Bool {
        guard let ss = self.stringSet else {
            return false
        }
        return ss.contains(str)
    }

    // add adds str to the set.
    func add(str: String) {
        if stringSet != nil {
            stringSet!.append(str)
        } else {
            stringSet = [str]
        }
    }

    // clean removes duplicates from the StringSet.
    func clean(isSuffix: Bool) {
        guard self.stringSet != nil else {
            return
        }

        if isSuffix {
            let sortedStringSet = stringSet!.sorted { s, t -> Bool in
                var index = 1
                while index <= s.count && index <= t.count {
                    let si = s[s.count - index]
                    let ti = t[t.count - index]
                    if si < ti {
                        return true
                    }
                    if si > ti {
                        return false
                    }
                    index += 1
                }
                return s.count < t.count
            }
            stringSet = Array<String>(sortedStringSet)
        } else {
            // TODO: Maybe use something like this?
            // let sorted = array.sorted {$0.localizedStandardCompare($1) == .orderedAscending}
            let sortedStringSet = stringSet!.sorted { $0 < $1 }
            stringSet = Array<String>(sortedStringSet)
        }
        var w = 0
        for str in self.stringSet! {
            if w == 0 || self.stringSet![w - 1] != str {
                self.stringSet![w] = str
                w += 1
            }
        }

        // TODO: Efficient enough to create a new array from array slice?
        self.stringSet = Array<String>(self.stringSet![..<w])
    }

    // size returns the number of strings in stringSet.
    func size() -> Int {
        return self.stringSet?.count ?? 0
    }

    // minLen returns the length of the shortest string in s.
    func minLen() -> Int {
        guard let ss = stringSet else {
            return 0
        }

        if ss.count == 0 {
            return 0
        }

        var min = ss.first!.count

        for str in ss {
            if min > str.count {
                min = str.count
            }
        }
        return min
    }

    // maxLen returns the length of the longest string in stringSet.
    func maxLen() -> Int {
        guard let ss = stringSet else {
            return 0
        }

        if ss.count == 0 {
            return 0
        }

        var max = ss.first!.count

        for str in ss {
            if max < str.count {
                max = str.count
            }
        }
        return max
    }

    // union returns the union of self and t, reusing stringSet's storage.
    func union(_ t: StringSet, isSuffix: Bool) -> StringSet {
        if self.stringSet == nil {
            self.stringSet = t.stringSet
        } else if t.stringSet != nil {
            self.stringSet!.append(contentsOf: t.stringSet!)
        }
        clean(isSuffix: isSuffix)
        return self
    }

    // cross returns the cross product of self and t.
    func cross(_ t: StringSet, isSuffix: Bool) -> StringSet {
        let p = StringSet()
        guard let s = stringSet else {
            return p
        }

        guard let ts = t.stringSet else {
            return p
        }

        for ss in s {
            for tt in ts {
                p.add(str: ss + tt)
            }
        }

        p.clean(isSuffix: isSuffix)
        return p
    }

    // clear empties the set but preserves the storage.
    func clear() {
        self.stringSet?.removeAll(keepingCapacity: false)
    }

    // copy returns a copy of the set that does not share storage with the original.
    func copy() -> StringSet {
        // TODO: Is this an actual copy?
        return StringSet(self.stringSet)
    }

    // isSubsetOf returns true if all strings in self are also in t.
    // It assumes both sets are sorted.
    func isSubset(of t: StringSet) -> Bool {
        // TODO: Is this the correct ordering for the guards?
        guard let s = self.stringSet else {
            // TODO: Does true make sense for a nil set being a subset of any other set?
            return true
        }

        guard let ts = t.stringSet else {
            return false
        }

        var j = 0
        for ss in s {
            while j < ts.count && ts[j] < ss {
                j += 1
            }
            if j >= ts.count || ts[j] != ss {
                return false
            }
        }
        return true
    }
}


// A Query is a matching machine, like a regular expression,
// that matches some text and not other text.  When we compute a
// Query from a regexp, the Query is a conservative version of the
// regexp: it matches everything the regexp would match, and probably
// quite a bit more.  We can then filter target files by whether they match
// the Query (using a trigram index) before running the comparatively
// more expensive regexp machinery.
class Query {
    var op: QueryOp
    var trigram: [String]
    var sub: [Query] // TODO: What should this be? Is []*Query in golang

    init(op: QueryOp, trigram: [String] = [], sub: [Query] = []) {
        self.op = op
        self.trigram = trigram
        self.sub = sub
    }

    // and returns the query q AND r, possibly reusing q's and r's storage.
    func and(_ r: Query) -> Query {
        return andOr(r, op: .QAnd)
    }

    // or returns the query q OR r, possibly reusing q's and r's storage.
    func or(_ r: Query) -> Query {
        return andOr(r, op: .QOr)
    }

    // andOr returns the query q AND r or q OR r, possibly reusing q's and r's storage.
    // It works hard to avoid creating unnecessarily complicated structures.
    func andOr(_ r: Query, op: QueryOp) -> Query {
        var opStr = "&"
        if op == .QOr {
            opStr = "|"
        }

        if self.trigram.count == 0 && self.sub.count == 1 {
            self.op = self.sub.first!.op
            self.trigram = self.sub.first!.trigram
            self.sub = self.sub.first!.sub
        }

        if r.trigram.count == 0 && r.sub.count == 1 {
            r.op = r.sub.first!.op
            r.trigram = r.sub.first!.trigram
            r.sub = r.sub.first!.sub
        }

        // Boolean simplification.
        // If q ⇒ r, q AND r ≡ q.
        // If q ⇒ r, q OR r ≡ r.
        if self.implies(r) {
            if op == .QAnd {
                return self
            }
            return r
        }

        if r.implies(self) {
            if op == .QAnd {
                return r
            }
            return self
        }

        // Both q and r are QAnd or QOr.
        // If they match or can be made to match, merge.
        let qAtom = self.trigram.count == 1 && self.sub.count == 0
        let rAtom = r.trigram.count == 1 && r.sub.count == 0

        if self.op == op && (r.op == op || rAtom) {
            self.trigram = StringSet(self.trigram).union(StringSet(r.trigram), isSuffix: false).stringSet!
            self.sub.append(contentsOf: r.sub)
            return self
        }
        if r.op == op && qAtom {
            // TODO: Not sure if we can be sure that the resulting string set will not be nil - presumably we can?
            r.trigram = StringSet(r.trigram).union(StringSet(self.trigram), isSuffix: false).stringSet ?? []
            return r
        }
        if qAtom && rAtom {
            self.op = op
            self.trigram.append(contentsOf: r.trigram)
            return self
        }

        // If one matches the op, add the other to it.
        if self.op == op {
            self.sub.append(r)
            return self
        }
        if r.op == op {
            r.sub.append(self)
            return r
        }

        // We are creating an AND of ORs or an OR of ANDs.
        // Factor out common trigrams, if any.
        let common = StringSet()
        var i = 0
        var j = 0
        var wi = 0
        var wj = 0

        while i < self.trigram.count && j < r.trigram.count {
            let qt = self.trigram[i]
            let rt = r.trigram[j]
            if qt < rt {
                self.trigram[wi] = qt
                wi += 1
                i += 1
            } else if qt > rt {
                r.trigram[wj] = rt
                wj += 1
                j += 1
            } else {
                common.add(str: qt)
                i += 1
                j += 1
            }
        }

        while i < self.trigram.count {
            self.trigram[wi] = self.trigram[i]
            wi += 1
            i += 1
        }

        while j < r.trigram.count {
            self.trigram[wi] = self.trigram[i]
            wj += 1
            j += 1
        }

        self.trigram = Array(self.trigram[..<wi])
        r.trigram = Array(r.trigram[..<wj])

        if common.size() > 0 {
            // If there were common trigrams, rewrite
            //
            //    (abc|def|ghi|jkl) AND (abc|def|mno|prs) =>
            //        (abc|def) OR ((ghi|jkl) AND (mno|prs))
            //
            //    (abc&def&ghi&jkl) OR (abc&def&mno&prs) =>
            //        (abc&def) AND ((ghi&jkl) OR (mno&prs))
            //
            // Build up the right one of
            //    (ghi|jkl) AND (mno|prs)
            //    (ghi&jkl) OR (mno&prs)
            // Call andOr recursively in case q and r can now be simplified
            // (we removed some trigrams).
            let s = self.andOr(r, op: op)

            let otherOpRaw = QueryOp.QAnd.rawValue + QueryOp.QOr.rawValue - op.rawValue
            let otherOp = QueryOp(rawValue: otherOpRaw)!

            // Add in factored trigrams.
            let t = Query(op: otherOp, trigram: common.stringSet ?? [])

            return t.andOr(s, op: t.op)
        }

        // Otherwise just create the op.
        return Query(op: op, trigram: [], sub: [self, r])
    }

    // implies reports whether q implies r.
    // It is okay for it to return false negatives.
    func implies(_ r: Query) -> Bool {
        if self.op == .QNone || r.op == .QAll {
            // False implies everything.
            // Everything implies True.
            return true
        }

        if self.op == .QAll || r.op == .QNone {
            // True implies nothing.
            // Nothing implies False.
            return false
        }

        if self.op == .QAnd || (self.op == .QOr && self.trigram.count == 1 && self.sub.count == 0) {
            return trigramsImply(t: self.trigram, q: r)
        }

        // TODO: Having to create two StringSet objects here is a bit gross
        if self.op == .QOr && r.op == .QOr && self.trigram.count > 0 && self.sub.count == 0 && StringSet(self.trigram).isSubset(of: StringSet(r.trigram)) {
            return true
        }

        return false
    }

    // maybeRewrite rewrites q to use op if it is possible to do so
    // without changing the meaning.  It also simplifies if the node
    // is an empty OR or AND.
    func maybeRewrite(op: QueryOp) {
        if self.op != .QAnd && self.op != .QOr {
            return
        }

        // AND/OR doing real work?  Can't rewrite.
        let n = self.sub.count + self.trigram.count
        if n > 1 {
            return
        }

        // Nothing left in the AND/OR?
        if n == 0 {
            if self.op == .QAnd {
                self.op = .QAll
            } else {
                self.op = .QNone
            }
            return
        }

        // Just a sub-node: throw away wrapper.
        if self.sub.count == 1 {
            self.op = self.sub.first!.op
            self.trigram = self.sub.first!.trigram
            self.sub = self.sub.first!.sub
        }

        // Just a trigram: can use either op.
        self.op = op
    }

    // andTrigrams returns q AND the OR of the AND of the trigrams present in each string.
    func andTrigrams(t: StringSet) -> Query {
        if t.minLen() < 3 {
            // If there is a short string, we can't guarantee
            // that any trigrams must be present, so use ALL.
            // q AND ALL = q.
            return self
        }

        let ts = t.stringSet!

        var or = noneQuery
        for tt in ts {
            let trig = StringSet()
            var i = 0
            while i + 3 < tt.count {
                trig.add(str: tt[i..<i+3])
                i += 1
            }
            trig.clean(isSuffix: false)

            or = or.or(Query(op: QueryOp.QAnd, trigram: trig.stringSet ?? []))
        }
        let new = self.and(or)
        self.op = new.op
        self.trigram = new.trigram
        self.sub = new.sub
        return self
    }

    func string() -> String {
        if self.op == .QNone {
            return "-"
        }
        if q.Op == QAll {
        return "+"
        }

        if len(q.Sub) == 0 && len(q.Trigram) == 1 {
        return strconv.Quote(q.Trigram[0])
        }

        var (
        s     string
        sjoin string
        end   string
        tjoin string
        )
        if q.Op == QAnd {
        sjoin = " "
        tjoin = " "
        } else {
        s = "("
        sjoin = ")|("
        end = ")"
        tjoin = "|"
        }
        for i, t := range q.Trigram {
        if i > 0 {
        s += tjoin
        }
        s += strconv.Quote(t)
        }
        if len(q.Sub) > 0 {
        if len(q.Trigram) > 0 {
        s += sjoin
        }
        s += q.Sub[0].String()
        for i := 1; i < len(q.Sub); i++ {
        s += sjoin + q.Sub[i].String()
        }
        }
        s += end
        return s
    }
}

enum QueryOp: Int {
    case QAll  // Everything matches
    case QNone // Nothing matches
    case QAnd  // All in sub and trigram must match
    case QOr   // At least one in sub or trigram must match
}

let allQuery = Query(op: .QAll)
let noneQuery = Query(op: .QNone)

func trigramsImply(t: [String], q: Query) -> Bool {
    switch q.op {
    case .QOr:
        for qq in q.sub {
            if trigramsImply(t: t, q: qq) {
                return true
            }
        }
        for i in t {
            if stringSet.isSubsetOf(t[i:i+1], q.Trigram) {
                return true
            }
        }
        return false
    case .QAnd:
        for qq in q.sub {
            if !trigramsImply(t: t, q: qq) {
                return false
            }
        }
        if !stringSet.isSubsetOf(q.trigram, t) {
            return false
        }
        return true
    default: return false
    }
}







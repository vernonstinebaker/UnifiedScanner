import Foundation

struct VendorModelExtractorService {
    struct Result { let vendor: String?; let model: String? }
    static func extract(from fingerprints: [String:String]) -> Result {
        var lower: [String:String] = [:]
        for (k,v) in fingerprints { lower[k.lowercased()] = v }
        let vendorKeys = ["vendor","manufacturer","brand","manu","mf","company"]
        let modelKeys = ["model","devicemodel","md","mdl","modelname","product","ty"]
        var vendor: String? = nil
        var model: String? = nil
        for k in vendorKeys { if let v = lower[k], !v.isEmpty { vendor = v; break } }
        for k in modelKeys { if let v = lower[k], !v.isEmpty { model = v; break } }
        if model == nil, let ty = lower["ty"], !ty.isEmpty { model = ty }
        return Result(vendor: vendor, model: model)
    }
}
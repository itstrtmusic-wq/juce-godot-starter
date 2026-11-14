#include "juce_dsp_network.h"
#include <godot_cpp/classes/json.hpp>
#include <initializer_list>

namespace godot {
namespace {
std::string text(const String& value) { return value.utf8().get_data(); }
bool number(const Variant& value) { return (value.get_type() == Variant::FLOAT || value.get_type() == Variant::INT) && std::isfinite(double(value)); }
bool string(const Variant& value) { return value.get_type() == Variant::STRING || value.get_type() == Variant::STRING_NAME; }
bool keys(const Dictionary& value, std::initializer_list<const char*> permitted) {
    for (const Variant& key : value.keys()) {
        if (!string(key)) return false;
        bool valid = false;
        for (const auto* name : permitted) if (String(key) == name) valid = true;
        if (!valid) return false;
    }
    return true;
}
}
bool JuceDSPNetwork::connect_parameter(const String& source, const String& destination, const String& parameter, float depth, float offset, int channel) {
    return graph.connect_parameter(text(source), text(destination), text(parameter), depth, offset, channel);
}
bool JuceDSPNetwork::disconnect_parameter(const String& source, const String& destination, const String& parameter) {
    return graph.disconnect_parameter(text(source), text(destination), text(parameter));
}
Array JuceDSPNetwork::get_modulation_connections() const {
    Array result;
    for (const auto& id : graph.node_ids()) for (const auto& m : graph.find(id)->modulations) {
        Dictionary item;
        item["source"] = String::utf8(m.source->id.c_str()); item["destination"] = String::utf8(id.c_str());
        item["parameter"] = m.target->name; item["depth"] = m.depth; item["offset"] = m.offset; item["channel"] = m.channel;
        result.append(item);
    }
    return result;
}
Dictionary JuceDSPNetwork::get_effective_parameters(const String& id) const {
    Dictionary result;
    if (const auto* node = graph.find(text(id))) for (const auto& p : node->parameters)
        result[p->name] = p->effective.load(std::memory_order_relaxed);
    return result;
}
Dictionary JuceDSPNetwork::export_patch() const {
    Dictionary patch; Array nodes;
    for (const auto& id : graph.node_ids()) {
        if (id == "input" || id == "output") continue;
        Dictionary node;
        node["id"] = String::utf8(id.c_str()); node["type"] = String::utf8(graph.find(id)->type.c_str());
        node["parameters"] = get_parameters(String::utf8(id.c_str())); nodes.append(node);
    }
    patch["schema_version"] = 1; patch["nodes"] = nodes;
    patch["connections"] = get_connections(); patch["modulations"] = get_modulation_connections();
    return patch;
}
bool JuceDSPNetwork::load_patch(const Dictionary& patch) {
    if (graph.active.load()) return graph.report_error("Stop audio before loading a patch");
    auto invalid = [&]() { return graph.report_error("Invalid patch schema or field type"); };
    if (!keys(patch, {"schema_version", "nodes", "connections", "modulations"}) || !patch.has("schema_version") ||
        !number(patch["schema_version"]) || double(patch["schema_version"]) != 1.0 ||
        !patch.has("nodes") || patch["nodes"].get_type() != Variant::ARRAY ||
        !patch.has("connections") || patch["connections"].get_type() != Variant::ARRAY ||
        (patch.has("modulations") && patch["modulations"].get_type() != Variant::ARRAY)) return invalid();
    const Array nodes = patch["nodes"], edges = patch["connections"];
    const Array mods = patch.has("modulations") ? Array(patch["modulations"]) : Array();
    if (nodes.size() > 62 || edges.size() + mods.size() > 256) return graph.report_error("Patch exceeds graph limits");
    bridge::DSPGraph candidate;
    auto failed = [&]() { return graph.report_error("Patch rejected: " + candidate.last_error()); };
    for (const Variant& raw : nodes) {
        if (raw.get_type() != Variant::DICTIONARY) return invalid();
        const Dictionary node = raw;
        if (!keys(node, {"id", "type", "parameters"}) || !node.has("id") || !node.has("type") ||
            !string(node["id"]) || !string(node["type"]) ||
            (node.has("parameters") && node["parameters"].get_type() != Variant::DICTIONARY)) return invalid();
        const String id = node["id"], type = node["type"];
        if (!candidate.add_node(text(id), text(type))) return failed();
        if (node.has("parameters")) {
            const Dictionary params = node["parameters"];
            for (const Variant& name : params.keys()) {
                if (!string(name) || !number(params[name])) return invalid();
                if (!candidate.set_parameter(text(id), text(String(name)), float(double(params[name])))) return failed();
            }
        }
    }
    for (const Variant& raw : edges) {
        if (raw.get_type() != Variant::DICTIONARY) return invalid();
        const Dictionary edge = raw;
        if (!keys(edge, {"source", "destination", "gain"}) || !edge.has("source") || !edge.has("destination") ||
            !string(edge["source"]) || !string(edge["destination"]) || (edge.has("gain") && !number(edge["gain"]))) return invalid();
        if (!candidate.connect(text(String(edge["source"])), text(String(edge["destination"])), edge.has("gain") ? float(double(edge["gain"])) : 1.0f)) return failed();
    }
    for (const Variant& raw : mods) {
        if (raw.get_type() != Variant::DICTIONARY) return invalid();
        const Dictionary m = raw;
        if (!keys(m, {"source", "destination", "parameter", "depth", "offset", "channel"}) ||
            !m.has("source") || !m.has("destination") || !m.has("parameter") ||
            !string(m["source"]) || !string(m["destination"]) || !string(m["parameter"]) ||
            (m.has("depth") && !number(m["depth"])) || (m.has("offset") && !number(m["offset"])) ||
            (m.has("channel") && (!number(m["channel"]) || double(m["channel"]) < 0 || double(m["channel"]) > 1 || std::floor(double(m["channel"])) != double(m["channel"])))) return invalid();
        if (!candidate.connect_parameter(text(String(m["source"])), text(String(m["destination"])), text(String(m["parameter"])),
            m.has("depth") ? float(double(m["depth"])) : 1.0f, m.has("offset") ? float(double(m["offset"])) : 0.0f,
            m.has("channel") ? int(m["channel"]) : 0)) return failed();
    }
    // Commit only after every node, parameter, edge and cross-kind cycle has been validated.
    return graph.replace_with(candidate);
}
bool JuceDSPNetwork::save_patch(const String& path, bool overwrite) {
    const String json = JSON::stringify(export_patch(), "  ");
    const auto utf8 = json.utf8();
    if (utf8.length() > 1048576) return graph.report_error("Patch exceeds 1 MiB limit");
    const auto target = juce_file_path(path);
    if (target.isDirectory()) return graph.report_error("Patch target is a directory");
    if (target.exists() && !overwrite) return graph.report_error("Patch target exists; explicitly enable overwrite");
    juce::TemporaryFile temp(target); auto stream = temp.getFile().createOutputStream();
    if (!stream || !stream->write(utf8.get_data(), size_t(utf8.length()))) return graph.report_error("Cannot write patch file");
    stream->flush(); const bool ok = stream->getStatus().wasOk(); stream.reset();
    if (!ok || !temp.overwriteTargetFileWithTemporary()) return graph.report_error("Cannot finish patch file");
    graph.clear_error(); return true;
}
bool JuceDSPNetwork::load_patch_file(const String& path) {
    if (graph.active.load()) return graph.report_error("Stop audio before loading a patch");
    const auto file = juce_file_path(path);
    if (!file.existsAsFile() || file.getSize() > 1048576) return graph.report_error("Patch is missing or exceeds 1 MiB limit");
    Ref<JSON> parser; parser.instantiate();
    if (parser->parse(gd_string(file.loadFileAsString())) != OK || parser->get_data().get_type() != Variant::DICTIONARY)
        return graph.report_error("Invalid patch JSON");
    return load_patch(Dictionary(parser->get_data()));
}
}

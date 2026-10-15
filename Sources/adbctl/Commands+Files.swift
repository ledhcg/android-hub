import AdbKit
import Foundation

func registerFileCommands() {
    register("device files list", "[path=/sdcard]", "List a directory on the device") { context in
        let path = context.rest.first ?? "/sdcard"
        let entries = try context.client.listDirectory(serial: try context.serial(), path: path)
        return CommandOutput(json: obj(("path", path), ("entries", entries))) {
            guard !entries.isEmpty else { return print("(empty)") }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            printTable(
                ["Permissions", "Size", "Modified", "Name"],
                entries.map { [$0.permissionString, $0.isDirectory ? "-" : formatBytes($0.size), formatter.string(from: $0.modified), $0.name + ($0.isDirectory ? "/" : "")] })
        }
    }

    register("device files pull", "<remote> [--output <directory>] [--force]", "Pull a file/directory from the device to this Mac") { context in
        let remote = try context.positional(0, "path on device")
        let directory = expandPath(context.args.option("--output", "-o") ?? ".")
        let local = try context.client.pull(serial: try context.serial(), remote: remote, toDirectory: directory, conflict: conflictPolicy(context.args))
        return CommandOutput(json: ["file": local.path]) { print(local.path) }
    }

    register("device files push", "<local> [remote-dir=/sdcard/Download]", "Push a file/directory from this Mac to the device") { context in
        let local = expandPath(try context.positional(0, "local file"))
        let remote = context.rest.count > 1 ? context.rest[1] : "/sdcard/Download"
        try context.client.push(serial: try context.serial(), local: local, toDirectory: remote)
        return CommandOutput(json: ["pushed": local.lastPathComponent, "to": remote]) { print("Pushed \(local.lastPathComponent) → \(remote)") }
    }

    register("device files mkdir", "<path>", "Create a directory") { context in
        let path = try context.positional(0, "path")
        try context.client.makeDirectory(serial: try context.serial(), path: path)
        return CommandOutput(json: ["created": path]) { print("Created \(path)") }
    }

    register("device files rm", "<path>", "Delete a file/directory") { context in
        let path = try context.positional(0, "path")
        try context.client.deleteFile(serial: try context.serial(), path: path)
        return CommandOutput(json: ["deleted": path]) { print("Deleted \(path)") }
    }

    register("device files mv", "<from> <to>", "Rename / move") { context in
        let from = try context.positional(0, "from")
        let to = try context.positional(1, "to")
        try context.client.renameFile(serial: try context.serial(), from: from, to: to)
        return CommandOutput(json: ["moved": to]) { print("\(from) → \(to)") }
    }
}

import Foundation

// Ecrit les exports d'exemple (voir Generateur.swift) sous le dossier donne en argument. Lance par
// outils/generer-exports-exemple.sh, qui compile ce fichier avec le contrat d'export.
let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage : generateur <dossier des exports>\n".utf8))
    exit(2)
}
do {
    try GenerateurExportsExemple.ecrireTout(dans: URL(fileURLWithPath: arguments[1], isDirectory: true))
} catch {
    FileHandle.standardError.write(Data("echec : \(error)\n".utf8))
    exit(1)
}

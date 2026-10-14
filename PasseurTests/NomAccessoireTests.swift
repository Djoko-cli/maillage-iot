import Testing

/// Le nom du releve : celui de la tuile s'il n'y en a qu'une, celui de l'accessoire sinon.
@Suite("Nom de l'accessoire")
struct NomAccessoireTests {
    @Test("Une seule tuile : son nom est utilise")
    func uneTuile() {
        #expect(NomAccessoire.affiche(accessoire: "Accessoire 1", tuiles: ["Vignette 1"]) == "Vignette 1")
    }

    @Test("Une seule tuile au nom vide ou blanc : le nom de l'accessoire")
    func tuileBlanche() {
        #expect(NomAccessoire.affiche(accessoire: "Accessoire 1", tuiles: [""]) == "Accessoire 1")
        #expect(NomAccessoire.affiche(accessoire: "Accessoire 1", tuiles: ["  \n "]) == "Accessoire 1")
    }

    @Test("Aucune tuile : le nom de l'accessoire")
    func sansTuile() {
        #expect(NomAccessoire.affiche(accessoire: "Accessoire 1", tuiles: []) == "Accessoire 1")
    }

    @Test("Plusieurs tuiles : le nom de l'accessoire")
    func plusieursTuiles() {
        #expect(NomAccessoire.affiche(accessoire: "Lampe", tuiles: ["Lampe", "Lampe avant", "Lampe arriere"]) == "Lampe")
        #expect(NomAccessoire.affiche(accessoire: "Accessoire 1", tuiles: ["Lampe avant", "Lampe arriere"]) == "Accessoire 1")
    }
}

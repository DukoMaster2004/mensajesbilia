import SwiftUI

struct AboutAppView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sobre esta aplicación")
                    .font(.title2.bold())

                Text("Esta aplicación fue creada con un propósito que va más allá de la tecnología: apoyar la vida espiritual y acercar la Palabra de Dios a todas las personas que desean conocerla, reflexionarla y fortalecer su fe.")

                Text("Nuestro objetivo no es obtener fines de lucro. Esta aplicación ha sido desarrollada como un proyecto pensado para el crecimiento espiritual y para brindar una experiencia sencilla, accesible y útil a quienes desean dedicar un momento de su día a Dios.")

                Text("Creemos que la tecnología también puede ser utilizada para compartir, aprender y fortalecer nuestra relación con Dios. Por eso, buscamos seguir mejorando la aplicación y escuchar a las personas que la utilizan.")

                sectionTitle("💡 Ayúdanos a mejorar")
                Text("Tu opinión es muy importante para nosotros. Si encuentras algún error, tienes una sugerencia, una idea para una nueva función o simplemente quieres compartir tu experiencia utilizando la aplicación, puedes dejarnos un comentario.")
                Text("También puedes enviarnos recomendaciones sobre:")
                VStack(alignment: .leading, spacing: 7) {
                    bullet("Nuevas funciones que te gustaría encontrar.")
                    bullet("Mejoras en el diseño y la experiencia de uso.")
                    bullet("Errores o problemas que hayas encontrado.")
                    bullet("Ideas relacionadas con el estudio y lectura de la Biblia.")
                    bullet("Funciones que puedan ayudar a otras personas en su crecimiento espiritual.")
                }
                Text("Cada comentario nos ayuda a entender qué podemos mejorar y cómo hacer que la aplicación sea cada vez más útil.")

                sectionTitle("🤝 Proyecto colaborativo")
                Text("Si eres desarrollador y tienes ideas para mejorar técnicamente la aplicación, puedes ponerte en contacto con nosotros.")
                Text("En caso de que quieras colaborar con el código, podemos evaluar tu propuesta y, cuando corresponda, compartir el código de manera privada y controlada para trabajar en conjunto.")
                Text("El código del proyecto no debe compartirse públicamente ni distribuirse a terceros sin autorización. Buscamos mantener el proyecto organizado y proteger tanto su desarrollo como los recursos que forman parte de la aplicación.")

                sectionTitle("❤️ Gracias por formar parte")
                Text("Gracias por utilizar esta aplicación, por compartir tus sugerencias y por ayudarnos a mejorarla.")
                Text("Nuestro deseo es que esta herramienta pueda ser de utilidad para cada persona que quiera acercarse a la Palabra de Dios y fortalecer su vida espiritual.")
                Text("Que esta aplicación sea una herramienta para aprender, reflexionar y acercarnos cada día más a Dios.")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Sobre esta aplicación")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.top, 6)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}
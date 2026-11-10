# Finanças (Flutter + Firebase)

Planilha financeira pessoal: o usuário registra ganhos e gastos, o app agrupa por
categoria e mostra um gráfico e barras que destacam o que mais pesa na renda.
Funciona em Android, iOS e Web com o mesmo código.

## 1. Criar o projeto Flutter e copiar os arquivos

```bash
flutter create financas_app --platforms=web,android,ios
cd financas_app
# copie lib/ e pubspec.yaml deste pacote por cima dos arquivos gerados
flutter pub get
```

## 2. Configurar o Firebase

1. Crie um projeto em https://console.firebase.google.com
2. **Authentication → Sign-in method**: ative **E-mail/senha** e **Google**.
3. **Firestore Database**: crie o banco (modo produção).
4. Na pasta do projeto:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   Isso gera `lib/firebase_options.dart` (o `main.dart` já importa esse arquivo).
5. **Web**: em Authentication → Settings → Authorized domains, adicione o domínio
   onde você vai publicar (localhost já vem liberado).
6. **Android**: adicione as impressões digitais SHA-1/SHA-256 do app no Firebase
   (`cd android && ./gradlew signingReport`) para o login Google funcionar.

## 3. Regras de segurança do Firestore (cada usuário só vê os próprios dados)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

## 4. Rodar e publicar

```bash
flutter run -d chrome          # testar na web
flutter build web --release    # gera build/web
firebase init hosting          # public dir: build/web, SPA: yes
firebase deploy                # publica em https://SEU-PROJETO.web.app
```

## Estrutura

```
lib/
  main.dart                  # Firebase, tema, alterna login/home
  models/tx.dart             # lançamento, categorias, sugestão automática
  models/user_settings.dart  # renda, meses de reserva, valor guardado
  services/auth_service.dart # e-mail/senha + Google
  services/tx_service.dart   # Firestore: users/{uid}/transactions
  services/settings_service.dart # Firestore: users/{uid}/settings/profile
  services/pdf_import_service.dart # extrai lançamentos de PDF de fatura
  pages/login_page.dart
  pages/home_page.dart       # resumo, metas, gráfico, categorias, lista, formulário
  widgets/goals_card.dart    # regra 50/30/20, reserva de emergência, diálogo de metas
  widgets/pdf_import_sheet.dart # revisão de itens importados do PDF
```

## Recursos

- **Lançamentos**: ganhos e gastos com categorias visuais e sugestão automática por palavra-chave
- **Parcelamento**: digite o valor da parcela, quantas são no total e em qual você está; o app calcula o total e gera as parcelas restantes
- **Recorrente**: lança automaticamente todo mês por N meses
- **Metas (50/30/20)**: essenciais, desejos e quanto guardar, com base na renda média
- **Reserva de emergência**: meta de 3 a 12 meses de gastos essenciais
- **Importar fatura (PDF)**: selecione o PDF da fatura do cartão, o app extrai os lançamentos e você categoriza cada um antes de salvar

> **Licença Syncfusion**: o pacote `syncfusion_flutter_pdf` exige uma licença Syncfusion válida (Community ou comercial). A partir da versão 18.3, não é necessário registrar a chave no código — basta possuir uma licença ativa. Saiba mais em [syncfusion.com/products/communitylicense](https://www.syncfusion.com/products/communitylicense).

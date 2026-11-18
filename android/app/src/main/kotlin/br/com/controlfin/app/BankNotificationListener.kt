package br.com.controlfin.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Recebe as notificações do celular (com o app fechado também) e guarda as
 * dos bancos que têm valor em reais. Quem decide o que cada texto significa
 * é o app, em Dart (bank_notification_parser.dart).
 *
 * Só funciona depois que o usuário libera em Configurações > Notificações >
 * Acesso a notificações.
 */
class BankNotificationListener : NotificationListenerService() {

    companion object {
        /**
         * Apps de banco lidos. Os seis primeiros foram conferidos num celular
         * de verdade (nov/2026); os outros são os nomes conhecidos na Play
         * Store e podem precisar de ajuste.
         */
        val BANK_PACKAGES = setOf(
            "com.nu.production",          // Nubank
            "br.com.xp.carteira",         // XP
            "com.itau",                   // Itaú
            "com.santander.app",          // Santander
            "com.mercadopago.wallet",     // Mercado Pago
            "com.google.android.apps.walletnfcrel", // Google Wallet (repete compras)
            "br.com.intermedium",         // Inter
            "com.c6bank.app",             // C6 Bank
            "com.bradesco",               // Bradesco
            "br.com.bb.android",          // Banco do Brasil
            "br.com.gabba.Caixa",         // Caixa
            "com.picpay",                 // PicPay
            "br.com.uol.ps.myaccount",    // PagBank
            "com.samsung.android.spay",   // Samsung Wallet (repete compras)
        )

        /** Carteiras do celular: repetem a compra do banco, sem aviso próprio. */
        private val WALLETS = setOf(
            "com.google.android.apps.walletnfcrel",
            "com.samsung.android.spay",
        )

        private const val CHANNEL_ID = "lancamentos_para_confirmar"

        /** Códigos e senhas nunca são guardados. */
        private val SECRET = Regex(
            "c[oó]digo|token|senha|\\bOTP\\b",
            RegexOption.IGNORE_CASE,
        )

        /** Parece movimentação (merece avisar o usuário na hora). */
        private val MOVEMENT = Regex(
            "aprovad|recebeu|recebemos|enviad|transferi|pix|cancelad|estorn|compra",
            RegexOption.IGNORE_CASE,
        )

        /** Propaganda e avisos com valor: guarda para validação, sem avisar. */
        private val PROMO = Regex(
            "\\b(ganhe|receba|deposite|aproveite|oferta|desconto|cashback|cupom|" +
                "limite|empr[eé]stimo|pr[eé]-aprovad|convide|sorteio|parcele)\\b",
            RegexOption.IGNORE_CASE,
        )
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        // Ao ligar o acesso, pega o que já está na barra (sem avisar).
        try {
            activeNotifications?.forEach { capture(it, prompt = false) }
        } catch (e: Exception) {
            // Sem acesso de fato: nada a fazer.
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        capture(sbn, prompt = true)
    }

    private fun capture(sbn: StatusBarNotification, prompt: Boolean) {
        val pkg = sbn.packageName
        if (pkg !in BANK_PACKAGES) return
        val notification = sbn.notification
        // O resumo de um grupo repete as notificações de dentro.
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.joinToString("\n")
        val body = (big?.takeIf { it.isNotBlank() } ?: text?.takeIf { it.isNotBlank() }
            ?: lines).orEmpty().trim()

        val all = "$title $body"
        if (!all.contains("R$")) return
        if (SECRET.containsMatchIn(all)) return

        val isNew = NotificationStore.add(this, pkg, title, body, sbn.postTime)
        if (isNew && prompt && pkg !in WALLETS &&
            MOVEMENT.containsMatchIn(all) && !PROMO.containsMatchIn(all)
        ) {
            showPrompt(body.ifBlank { title })
        }
    }

    /** "Confirme no ControlFin": abre o app na tela de confirmação. */
    private fun showPrompt(text: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Lançamentos para confirmar",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "Avisa quando uma notificação do banco vira um lançamento para confirmar."
                }
            )
        }
        val open = Intent(this, MainActivity::class.java)
            .putExtra(MainActivity.EXTRA_OPEN_INBOX, true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(
            this, 0, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_controlfin)
            .setContentTitle("Confirme no ControlFin")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        manager.notify(text.hashCode(), notification)
    }
}

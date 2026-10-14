// Crypto de l'ecoute MLE sur la carte : mbedTLS (SHA-256 et AES materiels du
// C6). Les tests hote fournissent la leur (sonde/test/test_mle.cpp,
// CommonCrypto). Appels depuis la tache loop seulement (ecoute.cpp).
#include <mbedtls/ccm.h>
#include <mbedtls/md.h>

#include "mle.h"

namespace mle {

bool hmacSha256(const uint8_t *cle, size_t nCle, const uint8_t *message, size_t n, uint8_t sortie[32]) {
  const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  return info != nullptr && mbedtls_md_hmac(info, cle, nCle, message, n, sortie) == 0;
}

bool aesCcmDechiffrer(const uint8_t cle[kCle], const uint8_t nonce[kNonce], const uint8_t *aad, size_t nAad,
                      const uint8_t *chiffre, size_t n, const uint8_t mic[kMic], uint8_t *clair) {
  mbedtls_ccm_context ccm;
  mbedtls_ccm_init(&ccm);
  int e = mbedtls_ccm_setkey(&ccm, MBEDTLS_CIPHER_ID_AES, cle, 128);
  if (e == 0) e = mbedtls_ccm_auth_decrypt(&ccm, n, nonce, kNonce, aad, nAad, chiffre, clair, mic, kMic);
  // Libere et efface le contexte (la cle etendue).
  mbedtls_ccm_free(&ccm);
  if (e != 0) effacer(clair, n);
  return e == 0;
}

}  // namespace mle

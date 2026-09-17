// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPrivacyLayer} from "./IPrivacyLayer.sol";

/**
 * @title IAuditableConfidentialSettlementDomain — extensão opcional de IPrivacyLayer
 *   para domínios que expõem uma política de auditoria e publicam uma trilha de
 *   auditoria on-chain.
 * @notice `auditAuthority()` e o evento `AuditableSecret` não pertencem ao núcleo
 *   (`IPrivacyLayer`) — vivem só aqui, como extensão.
 *
 *   Disponibilidade (o payload está publicado) é diferente de acesso (quem pode
 *   decriptar) e de disclosure (política de quando decriptar é legítimo). Esta
 *   interface cobre só a primeira; as outras duas são responsabilidade do
 *   contrato apontado por `auditAuthority()` (ex.: `HarpoSelectiveDisclosure`).
 *
 *   Um domínio concreto é livre para expor seu próprio mecanismo de emissão
 *   (ex.: `emitAuditableSecret`, em `HarpoZkPrivacyLayerAuditable`) como uma
 *   função adicional do contrato, fora desta interface compartilhada —
 *   `verifyConfidentialSettlement` é `view` e não pode emitir eventos.
 */
interface IAuditableConfidentialSettlementDomain is IPrivacyLayer {
    /// @notice Ponto de entrada da política de auditoria do domínio (address(0) se
    ///   o domínio não define autoridade de auditoria — equivalente a não
    ///   implementar esta extensão). PODE ser uma conta única, ou um contrato
    ///   representando uma política multi-parte (comitê de auditores M-de-N,
    ///   conjunto eleito por governança, controlador de disclosure com limite de
    ///   taxa...).
    function auditAuthority() external view returns (address);

    /// @notice Emitido quando material auditável associado a `commitment` fica
    ///   disponível para a autoridade de auditoria configurada do domínio.
    event AuditableSecret(bytes32 indexed commitment, bytes auditPayload);
}

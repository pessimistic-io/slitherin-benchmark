// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Term, ITerm, IERC165} from "./Term.sol";
import {ISignatures, IAgreementManager} from "./ISignatures.sol";

import {EIP712} from "./draft-EIP712.sol";
import {SignatureChecker} from "./SignatureChecker.sol";
import {EnumerableSet} from "./EnumerableSet.sol";

/// @notice Signature lines for Agreement.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/Signatures.sol)
contract Signatures is Term, ISignatures, EIP712 {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 private constant _TYPEHASH =
        keccak256('SignatureLine(address manager,uint256 tokenId,bytes32 agreementHash)');

    /// @dev Storage of required signers by Agreement ID
    mapping(IAgreementManager => mapping(uint256 => EnumerableSet.AddressSet)) internal signers;

    /// @dev Has the signer signed?
    mapping(IAgreementManager => mapping(uint256 => mapping(address => bool))) public signed;

    // solhint-disable-next-line no-empty-blocks
    constructor() EIP712('DinariSignatureTerm', '1') {}

    function constraintStatus(IAgreementManager manager, uint256 tokenId)
        public
        view
        virtual
        override(Term, ITerm)
        returns (uint256)
    {
        for (uint256 i = 0; i < signers[manager][tokenId].length(); i++) {
            if (!signed[manager][tokenId][signers[manager][tokenId].at(i)]) {
                return 0;
            }
        }
        return 100 ether;
    }

    function _createTerm(
        IAgreementManager manager,
        uint256 tokenId,
        bytes calldata data
    ) internal virtual override {
        address[] memory _signers = abi.decode(data, (address[]));
        for (uint256 i = 0; i < _signers.length; i++) {
            if (_signers[i] == address(0)) revert Term__ZeroAddress();
            if (!signers[manager][tokenId].add(_signers[i])) revert Signatures__Duplicate();
        }
    }

    function _settleTerm(IAgreementManager, uint256) internal virtual override {}

    function _cancelTerm(IAgreementManager, uint256) internal virtual override {}

    function _afterTermResolved(IAgreementManager manager, uint256 tokenId) internal virtual override {
        EnumerableSet.AddressSet storage _signers = signers[manager][tokenId];
        for (uint i = 0; i < _signers.length(); i++) {
            address signer = _signers.at(i);
            delete signed[manager][tokenId][signer];
            // slither-disable-next-line unused-return
            _signers.remove(signer);
        }

        super._afterTermResolved(manager, tokenId);
    }

    /// @inheritdoc ISignatures
    function submitSignature(
        address signer,
        SignatureLine calldata signatureLine,
        bytes calldata signature,
        string calldata note
    ) public virtual override {
        if (!signers[signatureLine.manager][signatureLine.tokenId].contains(signer)) revert Signatures__NotSigner();
        if (signed[signatureLine.manager][signatureLine.tokenId][signer]) revert Signatures__AlreadySigned();
        if (!SignatureChecker.isValidSignatureNow(signer, hashSignatureLine(signatureLine), signature))
            revert Signatures__InvalidSignature();

        signed[signatureLine.manager][signatureLine.tokenId][signer] = true;

        emit Signed(signatureLine.manager, signatureLine.tokenId, signer, signatureLine, signature, note);
    }

    /// @inheritdoc ISignatures
    function hashSignatureLine(SignatureLine calldata signatureLine) public view virtual override returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(_TYPEHASH, signatureLine.manager, signatureLine.tokenId, signatureLine.agreementHash)
                )
            );
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, Term) returns (bool) {
        return interfaceId == type(ISignatures).interfaceId || super.supportsInterface(interfaceId);
    }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ECDSAUpgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

// Uncomment this line to use console.log
import "./console.sol";

/// @dev TODO handle handling fee 
contract ApePayV1 is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using ECDSAUpgradeable for bytes32;

    // deadline for payment to be cancel-able. 1 hour
    // after deadline, payment can be claimed by recipient and sender
    uint256 private deadlineOffset;
    // nonce for payment sequence
    uint128 private _nonce;
    uint256 public feeBps; // 1 - 0.1% (actual fee is 0.1%)

    // pending payment 
    struct PaymentDetail {
        address sender;
        address token; // address of ERC20 token
        uint256 amount; // token amount
        uint128 nonce; // payment nonce
        uint256 deadline; // deadline before claim fund
        bool claimed;
    }

    // view only struct for frontend
    struct PaymentOverview {
        uint128[] all;
        uint128[] completed;
    }
    // view only array for frontend to query payment by sender address
    // sender => nonce[] for all payments. completed payment will still be stored in this array
    mapping(address => uint128[]) private AllPayments;
    // sender => nonce[] for completed payments
    mapping(address => uint128[]) private CompletedPayments;

    // nonce => PaymentDetail
    mapping(uint128 => PaymentDetail) private Payments;

    // address => whitelist gas payer
    // only gas payer can call receivePaymentDelegate
    mapping(address => bool) private GasPayers;

    // whitelisted token
    mapping(address => bool) private WhitelistedTokens;

    function initialize(address admin) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        // default set admin as gas payer
        GasPayers[admin] = true;
        deadlineOffset = 604800; // 1 week
        // feeBps = 9990; // 0.1% fee
        feeBps = 10000; 
        // changed something
        _nonce = 0;
        __EIP712_init("ApePay", "1");
    }

    function initEip712() public onlyOwner {
        __EIP712_init("ApePay", "1");
    }

    /// EVENT

    event PaymentCreated(
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint128 nonce,
        uint256 deadline
    );

    event PaymentReceived(
        address indexed recipient,
        uint128 nonce
    );

    event PaymentCancelled(
        address indexed sender,
        uint128 nonce
    );
    
    /// MODIFIER

    modifier onlyGasPayer() {
        require(GasPayers[msg.sender], "AP: not gas payer");
        _;
    }

    /// GET FUNCTION

    function getPaymentOverview(address user) public view returns (PaymentOverview memory) {
        return PaymentOverview(AllPayments[user], CompletedPayments[user]);
    }

    function bumpNonce() private returns (uint128) {
        uint128 nonce_ = _nonce;
        _nonce++;
        return nonce_;
    }

    function getPaymentDetail(uint128 nonce_) public view returns(PaymentDetail memory) {
        return Payments[nonce_];
    }

    function getPaymentDetails(uint128[] memory nonces) public view returns(PaymentDetail[] memory) {
        uint256 length = nonces.length;
        PaymentDetail[] memory details = new PaymentDetail[](length);
        for (uint256 index = 0; index < length; index++) {
            details[index] = Payments[nonces[index]];
        }
        return details;
    }

    function getDeadlineOffset() public view returns(uint256) {
        return deadlineOffset;
    }

    /// @dev convert payment params to hash
    /// recipientEmailHash is the keccak256 of recipientEmail
    function getPaymentHash(
        bytes32 recipientEmailHash,
        uint128 nonce_,
        bytes32 paymentId
    ) public pure returns(bytes32) {
        return keccak256(abi.encodePacked(recipientEmailHash, nonce_, paymentId));
    }

    function nonce() public view returns (uint128) {
        return _nonce;
    }

    // write function

    function addGasPayer(address gasPayer) external onlyOwner {
        GasPayers[gasPayer] = true;
    }

    function addGasPayers(address[] memory gasPayers) external onlyOwner {
        uint256 length = gasPayers.length;
        for (uint256 index = 0; index < length; index++) {
            GasPayers[gasPayers[index]] = true;
        }
    }

    function removeGasPayer(address gasPayer) external onlyOwner {
        GasPayers[gasPayer] = false;
    }

    function removeGasPayers(address[] memory gasPayers) external onlyOwner {
        uint256 length = gasPayers.length;
        for (uint256 index = 0; index < length; index++) {
            GasPayers[gasPayers[index]] = false;
        }
    }

    function whitelistTokens(address[] memory tokens) external onlyOwner {
        uint256 length = tokens.length;
        for (uint256 index = 0; index < length; index++) {
            WhitelistedTokens[tokens[index]] = true;
        }
    }

    function removeTokens(address[] memory tokens) external onlyOwner {
        uint256 length = tokens.length;
        for (uint256 index = 0; index < length; index++) {
            WhitelistedTokens[tokens[index]] = false;
        }
    }

    function setFeeBps(uint256 feeBps_) external onlyOwner {
        feeBps = feeBps_;
    }

    function setDeadlineOffset(uint256 deadlineOffset_) external onlyOwner {
        deadlineOffset = deadlineOffset_;
    }

    /// @dev no-longer requires caller to provide nonce. nonce is auto-incremented
    /// @dev only use this if no need custom deadline => default deadlineOffset will be used
    function createPayment(
        uint256 amount,
        address token
    ) external payable nonReentrant {
        // check and bump nonce
        // check if the token is whitelisted
        _createPayment(amount, token, deadlineOffset);
    }

    /// overload createPayment to allow custom deadline. offset should be in seconds
    function createPaymentV2(
        uint256 amount,
        address token,
        uint256 deadlineOffset_
    ) external payable nonReentrant {
        // check and bump nonce
        // check if the token is whitelisted
        _createPayment(amount, token, deadlineOffset_);
    }

    function _createPayment(
        uint256 amount,
        address token,
        uint256 deadlineOffset_
    ) private {
        require(WhitelistedTokens[token], "AP: token not whitelisted");
        uint128 nonce_ = bumpNonce();
        address sender = msg.sender;
        uint256 deadline = block.timestamp + deadlineOffset_;
        // transfer token
        if (token == address(0)) {
            // ETH
            require(msg.value == amount, "AP: invalid amount");
        } else {
            IERC20(token).safeTransferFrom(sender, address(this), amount);
        }
        // change state: payment detail
        Payments[nonce_] = PaymentDetail(
            sender,
            token,
            amount,
            nonce_,
            deadline,
            false
        );
        // change state: payment overview
        AllPayments[sender].push(nonce_);

        emit PaymentCreated(sender, token, amount, nonce_, deadline);
    }

    function _cancelPayment(uint128[] memory nonces, bool isOwner) private {
        for (uint256 i = 0; i < nonces.length; i++) {
            uint128 nonce_ = nonces[i];
            PaymentDetail memory paymentDetail = Payments[nonce_];
            require(isOwner || paymentDetail.sender == msg.sender, "AP: not sender");
            require(paymentDetail.claimed == false, "AP: payment claimed already");
            // refund fund
            sendFund(paymentDetail, paymentDetail.sender);

            emit PaymentCancelled(msg.sender, nonce_);
        }
    }

    function cancelPayment(uint128[] memory nonces) external nonReentrant {
        _cancelPayment(nonces, false);
    }

    function cancelPaymentByAdmin(uint128[] memory nonces) external nonReentrant onlyOwner {
        _cancelPayment(nonces, true);
    }

    /// @dev use eip712 standard for verifying signature
    /// @param message string containing the recipient email identity
    function verifyRecipient(
        bytes32 paymentId,
        string memory message,
        uint128 nonce_,
        bytes memory signature
    ) public view returns(PaymentDetail memory) {
        // verify payment details
        // verify signature
        PaymentDetail memory paymentDetail = Payments[nonce_];
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            keccak256("Payment(string message,bytes32 paymentId,uint128 nonce)"),
            keccak256(bytes(message)),
            paymentId,
            nonce_
        )));
        address paymentSender = ECDSAUpgradeable.recover(digest, signature);
        // if the signature is correct, we should recover the sender address
        require(paymentSender == paymentDetail.sender, "AP: not sender");
        require(paymentDetail.claimed == false, "AP: payment claimed already");
        return paymentDetail;
    }

    /// @dev verify the recipient has delegated the gas payer to call this txn on its behalf
    function _isDelegateReceive(
        uint128 nonce_,
        address recipient,
        bytes memory recipientSignature
    ) private pure {
        // the signed message is composed of the payment nonce to prevent the signature from being reused
        bytes32 message = ECDSAUpgradeable.toEthSignedMessageHash(keccak256(abi.encodePacked(nonce_)));
        address paymentRecipient = ECDSAUpgradeable.recover(message, recipientSignature);
        require(paymentRecipient == recipient, "AP: not recipient");
    }

    // function receivePayment(
    //     bytes32 paymentId,
    //     string memory message,
    //     uint128 nonce_,
    //     bytes memory signature
    // ) external nonReentrant {
    //     revert('AP: deprecated');
    //     // _receivePayment(paymentId, message, nonce_, signature, msg.sender);
    // }
    
    // receive payment from gas payer on behalf of recipient
    /// @param nonce_ nonce of payment
    /// @param senderSignature signature of sender to proof the recipient is valid
    /// @param message string message container recipient identity
    function receivePaymentDelegate(
        bytes32 paymentId,
        string memory message,
        uint128 nonce_,
        bytes memory senderSignature,
        address recipientAddress
    ) external nonReentrant onlyGasPayer {
        // 1. verify delegation
        // we need to know the txn is delegated by the recipient
        _receivePayment(paymentId, message, nonce_, senderSignature, recipientAddress);
    }

    function _receivePayment(
        bytes32 paymentId,
        string memory message,
        uint128 nonce_,
        bytes memory signature,
        address recipientAddress
    ) private {
        PaymentDetail memory paymentDetail = verifyRecipient(paymentId, message, nonce_, signature);
        require(paymentDetail.deadline > block.timestamp, "AP: payment expired");
        // send fund
        // modify the paymentDetail.amount to collect fee
        paymentDetail.amount = paymentDetail.amount * feeBps / 10000; // always round down
        sendFund(paymentDetail, recipientAddress);

        emit PaymentReceived(recipientAddress, nonce_);
    }


    /// @dev call before sending fund. this function does not do validation. 
    function beforeSendFund(PaymentDetail memory paymentDetail) private {
        // state update: set payment as claimed
        Payments[paymentDetail.nonce].claimed = true;
        // state update: add nonce to completed payment
        CompletedPayments[paymentDetail.sender].push(paymentDetail.nonce);
    }

    /// @dev private function to send fund. 
    // it handles the case of ETH and ERC20 token. does not do validation.
    // will handle the clean-up state update to set the payment as done
    function sendFund(
        PaymentDetail memory paymentDetail,
        address recipient
    ) private {
        beforeSendFund(paymentDetail);
        // send fund
        if (paymentDetail.token == address(0)) {
            // ETH
            payable(recipient).transfer(paymentDetail.amount);
            return;
        }
        IERC20(paymentDetail.token).safeTransfer(recipient, paymentDetail.amount);
    }

    /* solhint-disable var-name-mixedcase */
    bytes32 private _HASHED_NAME;
    bytes32 private _HASHED_VERSION;
    bytes32 private constant _TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /* solhint-enable var-name-mixedcase */

    /**
     * @dev Initializes the domain separator and parameter caches.
     *
     * The meaning of `name` and `version` is specified in
     * https://eips.ethereum.org/EIPS/eip-712#definition-of-domainseparator[EIP 712]:
     *
     * - `name`: the user readable name of the signing domain, i.e. the name of the DApp or the protocol.
     * - `version`: the current major version of the signing domain.
     *
     * NOTE: These parameters cannot be changed except through a xref:learn::upgrading-smart-contracts.adoc[smart
     * contract upgrade].
     */
    function __EIP712_init(string memory name, string memory version) internal {
        __EIP712_init_unchained(name, version);
    }

    function __EIP712_init_unchained(string memory name, string memory version) internal {
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes(version));
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4() public view returns (bytes32) {
        return _buildDomainSeparator(_TYPE_HASH, _EIP712NameHash(), _EIP712VersionHash());
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash
    ) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, nameHash, versionHash, block.chainid, address(this)));
    }

    /**
     * @dev Given an already https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct[hashed struct], this
     * function returns the hash of the fully encoded EIP712 message for this domain.
     *
     * This hash can be used together with {ECDSA-recover} to obtain the signer of a message. For example:
     *
     * ```solidity
     * bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
     *     keccak256("Mail(address to,string contents)"),
     *     mailTo,
     *     keccak256(bytes(mailContents))
     * )));
     * address signer = ECDSA.recover(digest, signature);
     * ```
     */
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return ECDSAUpgradeable.toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    /**
     * @dev The hash of the name parameter for the EIP712 domain.
     *
     * NOTE: This function reads from storage by default, but can be redefined to return a constant value if gas costs
     * are a concern.
     */
    function _EIP712NameHash() internal virtual view returns (bytes32) {
        return _HASHED_NAME;
    }

    /**
     * @dev The hash of the version parameter for the EIP712 domain.
     *
     * NOTE: This function reads from storage by default, but can be redefined to return a constant value if gas costs
     * are a concern.
     */
    function _EIP712VersionHash() internal virtual view returns (bytes32) {
        return _HASHED_VERSION;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}


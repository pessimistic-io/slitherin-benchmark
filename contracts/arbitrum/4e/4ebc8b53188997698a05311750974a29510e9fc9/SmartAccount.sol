// SPDX-License-Identifier: MIT
// The line above is recommended and let you define the license of your contract
// Solidity files have to start with this pragma.
// It will be used by the Solidity compiler to validate its version.
pragma solidity ^0.8.0;
import "./BeaconProxy.sol";
import "./UpgradeableBeacon.sol";
import "./ECDSAUpgradeable.sol";
import "./Initializable.sol";
import "./IBeaconUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ISmartAccount.sol";
import "./IFarm.sol";
import "./IRegistry.sol";
import "./IBridge.sol";
import "./ISocketRegistry.sol";
import "./IERC20MetadataUpgradeable.sol";

/**
 * @dev https://eips.ethereum.org/EIPS/eip-712[EIP 712] is a standard for hashing and signing of typed structured data.
 *
 * The encoding specified in the EIP is very generic, and such a generic implementation in Solidity is not feasible,
 * thus this contract does not implement the encoding itself. Protocols need to implement the type-specific encoding
 * they need in their contracts using a combination of `abi.encode` and `keccak256`.
 *
 * This contract implements the EIP 712 domain separator ({_domainSeparatorV4}) that is used as part of the encoding
 * scheme, and the final step of the encoding to obtain the message digest that is then signed via ECDSA
 * ({_hashTypedDataV4}).
 *
 * The implementation of the domain separator was designed to be as efficient as possible while still properly updating
 * the chain id to protect against replay attacks on an eventual fork of the chain.
 *
 * NOTE: This contract implements the version of the encoding known as "v4", as implemented by the JSON RPC method
 * https://docs.metamask.io/guide/signing-data.html[`eth_signTypedDataV4` in MetaMask].
 *
 * _Available since v3.4._
 */
abstract contract EIP712Upgradeable is Initializable {
    /* solhint-disable var-name-mixedcase */
    bytes32 private _HASHED_NAME;
    bytes32 private _HASHED_VERSION;
    bytes32 private constant _TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

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
    function __EIP712_init(string memory name, string memory version)
        internal
        onlyInitializing
    {
        __EIP712_init_unchained(name, version);
    }

    function __EIP712_init_unchained(string memory name, string memory version)
        internal
        onlyInitializing
    {
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes(version));
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4(uint256 chainId)
        internal
        view
        returns (bytes32)
    {
        return
            _buildDomainSeparator(
                _TYPE_HASH,
                _EIP712NameHash(),
                _EIP712VersionHash(),
                chainId
            );
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash,
        uint256 chainId
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    typeHash,
                    nameHash,
                    versionHash,
                    chainId,
                    address(this)
                )
            );
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
    function _hashTypedDataV4(bytes32 structHash, uint256 chainId)
        internal
        view
        virtual
        returns (bytes32)
    {
        return
            ECDSAUpgradeable.toTypedDataHash(
                _domainSeparatorV4(chainId),
                structHash
            );
    }

    /**
     * @dev The hash of the name parameter for the EIP712 domain.
     *
     * NOTE: This function reads from storage by default, but can be redefined to return a constant value if gas costs
     * are a concern.
     */
    function _EIP712NameHash() internal view virtual returns (bytes32) {
        return _HASHED_NAME;
    }

    /**
     * @dev The hash of the version parameter for the EIP712 domain.
     *
     * NOTE: This function reads from storage by default, but can be redefined to return a constant value if gas costs
     * are a concern.
     */
    function _EIP712VersionHash() internal view virtual returns (bytes32) {
        return _HASHED_VERSION;
    }

    uint256[50] private __gap;
}

contract SmartAccountBeacon is UpgradeableBeacon {
    constructor(address beacon) payable UpgradeableBeacon(beacon) {}
}

contract SmartAccountFactory is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ISmartAccountFactory
{
    IBeaconUpgradeable public override beacon;
    IConfig public override config;
    mapping(address => ISmartAccount) public override smartAccount;

    function _initialize(IBeaconUpgradeable b, IConfig c) public initializer {
        OwnableUpgradeable.__Ownable_init();
        beacon = b;
        config = c;
    }

    function _getByteCode(address user)
        internal
        view
        returns (bytes memory byteCode)
    {
        byteCode = abi.encodePacked(
            type(BeaconProxy).creationCode,
            abi.encode(
                beacon,
                abi.encodeWithSelector(
                    SmartAccount._initialize.selector,
                    config,
                    user
                )
            )
        );
    }

    function precomputeAddress(address user)
        public
        view
        override
        returns (address addr)
    {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                address(this),
                                uint256(uint160(user)),
                                keccak256(_getByteCode(user))
                            )
                        )
                    )
                )
            );
    }

    function createSmartAccount(address user)
        external
        override
        onlyOwner
        nonReentrant
        whenNotPaused
    {
        require(address(smartAccount[user]) == address(0), "SA1");
        address addr = precomputeAddress(user);
        uint256 s = 0;
        assembly {
            s := extcodesize(addr)
        }
        require(s == 0, "SA2");
        bytes memory byteCode = _getByteCode(user);
        uint256 salt = uint256(uint160(user));
        assembly {
            addr := create2(
                callvalue(), // wei sent with current call
                // Actual code starts after skipping the first 32 bytes
                add(byteCode, 0x20),
                mload(byteCode), // Load the size of code contained in the first 32 bytes
                salt // Salt from function arguments
            )
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        smartAccount[user] = ISmartAccount(addr);
        emit SmartAccountCreated(user, addr);
    }

    function execute(ISmartAccount.ExecuteParams calldata x, address signer)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        ISmartAccount sa = smartAccount[signer];
        require(address(sa) != address(0), "SA3");
        sa.execute(x);
        emit Execute(signer, address(sa), x);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

contract SmartAccount is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    ISmartAccount
{
    bytes32 public constant OPERATIONS_TYPEHASH =
        keccak256(
            "Operations(uint256 executeChainId,uint256 signatureChainId,Operation[] operations,bytes32 nonce)Operation(address integration,address token,uint256 value,bytes data)"
        );
    bytes32 public constant OPERATION_TYPEHASH =
        keccak256(
            "Operation(address integration,address token,uint256 value,bytes data)"
        );
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    using ECDSAUpgradeable for bytes32;
    IConfig public override config;
    mapping(bytes32 => bool) public nonceUsed;

    function _initialize(IConfig c, address user) public initializer {
        EIP712Upgradeable.__EIP712_init("SmartAccount", "1");
        _transferOwnership(user);
        config = c;
    }

    function _resolveSigner(ExecuteParams calldata x)
        internal
        view
        returns (address signer)
    {
        bytes memory operations;
        for (uint256 i; i < x.operations.length; i++) {
            operations = bytes.concat(
                operations,
                keccak256(
                    abi.encode(
                        OPERATION_TYPEHASH,
                        address(x.operations[i].integration),
                        address(x.operations[i].token),
                        x.operations[i].value,
                        keccak256(x.operations[i].data)
                    )
                )
            );
        }
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    OPERATIONS_TYPEHASH,
                    block.chainid,
                    x.signatureChainId,
                    keccak256(operations),
                    x.nonce
                )
            ),
            x.signatureChainId
        );
        signer = digest.recover(x.v, x.r, x.s);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function execute(ExecuteParams calldata x)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(!nonceUsed[x.nonce], "SA3");
        IRegistry reg = config.registry();
        address o = owner();
        address signer = _resolveSigner(x);
        require(signer == o, "SA4");

        for (uint256 i; i < x.operations.length; i++) {
            Operation calldata op = x.operations[i];
            require(reg.integrationExist(op.integration), "SA5");
            uint256 s = 0;
            // check x.integration has extcodesize
            address addr = op.integration;
            assembly {
                s := extcodesize(addr)
            }
            require(s > 0, "SA6");
            (bool success, bytes memory returndata) = op
                .integration
                .delegatecall(op.data);
            require(success, string(returndata));
        }
        // Note: Here we are checking the source chain ID instead of the current chain, since the message might be signed on a different chain!
        nonceUsed[x.nonce] = true;
        emit Execute(x);
    }

    function withdrawToken(IERC20MetadataUpgradeable token, uint256 amount)
        external
        override
        nonReentrant
        onlyOwner
    {
        address o = owner();
        token.safeTransfer(o, amount);
        emit TokenWithdrawn(token, o, amount);
    }

    function withdrawNative(uint256 amount)
        external
        override
        nonReentrant
        onlyOwner
    {
        address payable o = payable(owner());
        o.transfer(amount);
        emit NativeWithdrawn(o, amount);
    }

    function portfolio()
        external
        view
        returns (IRegistry.AccountPosition[] memory result)
    {
        return config.registry().portfolio(address(this));
    }

    // able to receive ether
    receive() external payable {}
}


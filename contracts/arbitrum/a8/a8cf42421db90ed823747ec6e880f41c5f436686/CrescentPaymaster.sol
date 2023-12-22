// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./IEntryPoint.sol";
import "./ECDSA.sol";
import "./Initializable.sol";
import "./EntryPointController.sol";
import "./CrescentBasePaymaster.sol";

contract CrescentPaymaster is CrescentBasePaymaster, Initializable {

    using ECDSA for bytes32;
    using UserOperationLib for UserOperation;

    uint256 private constant SIGNATURE_OFFSET = 20;

    EntryPointController public entryPointController;

    address public create2Factory;

    address public verifyingSigner;

    address public walletController;

    address public dkimVerifier;

    bytes32 public crescentWalletHash;

    mapping (address => bool) private supportWallets;

    mapping (bytes32 => address) private wallets;


    function initialize(address _create2Factory, address _entryPointController, address _walletController, address _dkimVerifier, address _verifyingSigner, bytes32 _crescentWalletHash) external initializer {
        require(_create2Factory != address(0), "invalid create2Factory");
        require(_entryPointController != address(0), "invalid entryPointController");
        require(_walletController != address(0), "invalid walletController");
        require(_dkimVerifier != address(0), "invalid dkimVerifier");
        require(_verifyingSigner != address(0), "invalid verifyingSigner");
        
        _transferOwnership(_msgSender());
        create2Factory = _create2Factory;
        entryPointController = EntryPointController(payable(_entryPointController));

        verifyingSigner = _verifyingSigner;
        crescentWalletHash = _crescentWalletHash;
        walletController = _walletController;
        dkimVerifier = _dkimVerifier;
    }

    function entryPoint() public view virtual override returns (IEntryPoint) {
        return IEntryPoint(entryPointController.getEntryPoint());
    }

    function setEntryPointController(address _entryPointController) public onlyOwner {
        require(address(entryPointController) != _entryPointController);
        entryPointController = EntryPointController(_entryPointController);
    }

    function setVerifyingSigner(address _verifyingSigner) public onlyOwner {
        require(verifyingSigner != _verifyingSigner);
        verifyingSigner = _verifyingSigner;
    }

    function setWalletController(address _walletController) public onlyOwner {
        require(walletController != _walletController);
        walletController = _walletController;
    }

    function setCrescentWalletHash(bytes32 _crescentWalletHash) public onlyOwner {
        require(crescentWalletHash != _crescentWalletHash);
        crescentWalletHash = _crescentWalletHash;
    }

    function getWallet(bytes32 salt) public view returns (address) {
        return wallets[salt];
    }

    function supportWallet(address wallet) public view returns (bool) {
        return supportWallets[wallet];
    }

    /**
     * return the hash we're going to sign off-chain (and validate on-chain)
     * this method is called by the off-chain service, to sign the request.
     * it is called on-chain from the validatePaymasterUserOp, to validate the signature.
     * note that this signature covers all fields of the UserOperation, except the "paymasterData",
     * which will carry the signature itself.
     */
    function getHash(UserOperation calldata userOp)
    public view returns (bytes32) {
        //can't use userOp.hash(), since it contains also the paymasterData itself.
        return keccak256(abi.encode(
                userOp.getSender(),
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.callGasLimit,
                userOp.verificationGasLimit,
                userOp.preVerificationGas,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                block.chainid,
                address(this)
            ));
    }

    function parsePaymasterAndData(bytes calldata paymasterAndData) public pure returns(bytes calldata signature) {
        signature = paymasterAndData[SIGNATURE_OFFSET:];
    }

    /**
     * verify our external signer signed this request.
     * the "paymasterData" is supposed to be a signature over the entire request params
     */
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
    internal virtual override returns (bytes memory context, uint256 validationData) {
        (userOpHash, maxCost);

        _validateConstructor(userOp);

        bytes32 hash = getHash(userOp);
        (bytes calldata signature) = parsePaymasterAndData(userOp.paymasterAndData);
        uint256 sigLength = signature.length;
        require(sigLength == 64 || sigLength == 65, "CrescentPaymaster: invalid signature length in paymasterData");

        if (verifyingSigner != hash.toEthSignedMessageHash().recover(signature)) {
            return ("", _packValidationData(true,0,0));
        }

        if (userOp.initCode.length > 0) {
            bytes32 hmua = bytes32(userOp.initCode[userOp.initCode.length - 40 :]);
            return (abi.encode(hmua, userOp.getSender()), _packValidationData(false,0,0));
        }
        return ("", _packValidationData(false,0,0));
    }

    function _validateConstructor(UserOperation calldata userOp) internal virtual view {
        if (userOp.initCode.length == 0) {
            return;
        }
        address factory = address(bytes20(userOp.initCode[0 : 20]));
        require(create2Factory == factory, "wrong factory in constructor");

        bytes32 bytecodeHash = keccak256(userOp.initCode[120 : userOp.initCode.length - 136]);
        require(crescentWalletHash == bytecodeHash, "CrescentPaymaster: unknown wallet constructor");

        bytes32 entryPointParam = bytes32(userOp.initCode[userOp.initCode.length - 136 :]);
        require(address(uint160(uint256(entryPointParam))) == address(entryPointController), "wrong entryPointController in constructor");

        bytes32 walletControllerParam = bytes32(userOp.initCode[userOp.initCode.length - 104 :]);
        require(address(uint160(uint256(walletControllerParam))) == walletController, "wrong wallet controller in constructor");

        bytes32 dkimVerifierParam = bytes32(userOp.initCode[userOp.initCode.length - 72 :]);
        require(address(uint160(uint256(dkimVerifierParam))) == dkimVerifier, "wrong dkim verifier in constructor");
    }

    /**
     * actual charge of user.
     * this method will be called just after the user's TX with mode==OpSucceeded|OpReverted (wallet pays in both cases)
     * BUT: if the user changed its balance in a way that will cause  postOp to revert, then it gets called again, after reverting
     * the user's TX , back to the state it was before the transaction started (before the validatePaymasterUserOp),
     * and the transaction should succeed there.
     */
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {
        (mode);
        (actualGasCost);
        if (context.length == 64) {
            bytes32 hmua = bytes32(context);
            address sender = address(uint160(uint256(bytes32(context[32:]))));
            wallets[hmua] = sender;
            supportWallets[sender] = true;
        }
    }
}


// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Strings.sol";
import "./Address.sol";
import "./Context.sol";
import "./ECDSA.sol";
import "./IERC20.sol";
import "./Initializable.sol";
import "./BaseAccount.sol";
import "./UserOperation.sol";
import "./IEntryPoint.sol";
import "./VerifierInfo.sol";
import "./EntryPointController.sol";

interface IVerifier{
    function verifier(
        address owner,
        bytes32 hmua,
        VerifierInfo calldata info
    ) external view;
}

contract CrescentWallet is BaseAccount, Initializable {

    using ECDSA for bytes32;
    using UserOperationLib for UserOperation;
    bytes4 constant internal MAGICVALUE = 0x1626ba7e; // EIP-1271 magic value

    uint96 private _nonce;

    bytes32 public hmua;

    address[] private allOwner;
    mapping (address => uint16) private owners;

    address public dkimVerifier;

    EntryPointController public entryPointController;

    function nonce() public view virtual override returns (uint256) {
        return _nonce;
    }

    function entryPoint() public view virtual override returns (IEntryPoint) {
        return IEntryPoint(entryPointController.getEntryPoint());
    }

    function initialize(address _entryPointController, address _dkimVerifier, bytes32 _hmua) external initializer {
        require(_entryPointController != address(0), "invalid entryPointController");
        require(_dkimVerifier != address(0), "invalid dkimVerifier");
        entryPointController = EntryPointController(payable(_entryPointController));
        dkimVerifier = _dkimVerifier;
        hmua = _hmua;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    modifier onlyAdmin() {
        require(msg.sender == address(this) || msg.sender == address(entryPoint()), "not admin");
        _;
    }

    modifier onlyEntryPoint() {
        require(msg.sender == address(entryPoint()), "not admin");
        _;
    }


    function addOwner(
        address owner,
        VerifierInfo calldata info
    ) external onlyEntryPoint {
        require(allOwner.length < type(uint16).max, "Too many owners");
        require(owners[owner] == 0, "Owner already exists");
        IVerifier(dkimVerifier).verifier(owner, hmua, info);
        uint16 index = uint16(allOwner.length + 1);
        allOwner.push(owner);
        owners[owner] = index;
    }

    function deleteOwner(address owner) external onlyAdmin {
        require(owners[owner] != 0, "The owner does not exist");
        for (uint i = owners[owner] - 1; i < allOwner.length - 1; i++){
            allOwner[i] = allOwner[i + 1];
        }
        allOwner.pop();

        delete owners[owner];
    }

    function clearOwner() external onlyAdmin {
        uint16 length = uint16(allOwner.length);
        for (uint16 i = 0; i < length; i++) {
            delete owners[allOwner[i]];
        }
        delete allOwner;
    }

    function containOwner(address owner) public view returns (bool) {
        return owners[owner] > 0;
    }

    function execFromEntryPoint(address dest, uint256 value, bytes calldata func) external onlyEntryPoint {
        _call(dest, value, func);
    }

    /**
     * transfer eth value to a destination address
     */
    function transfer(address payable dest, uint256 amount) external onlyAdmin {
        _call(dest, amount, "");
    }

    /**
     * execute a transaction (called directly from owner, not by entryPoint)
     */
    function exec(address dest, uint256 value, bytes calldata func) external onlyAdmin {
        _call(dest, value, func);
    }

    /**
     * execute a sequence of transaction
     */
    function execBatch(address[] calldata dest, bytes[] calldata func) external onlyAdmin {
        require(dest.length == func.length, "wrong array lengths");
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value : value}(data);
        if (!success) {
            assembly {
                revert(add(result,32), mload(result))
            }
        }
    }

    /// implement template method of BaseWallet
    function _validateAndUpdateNonce(UserOperation calldata userOp) internal override {
        require(_nonce++ == userOp.nonce, "wallet: invalid nonce");
    }

    /// implement template method of BaseWallet
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
    internal override virtual returns (uint256 validationData) {
        bool isAddOwner = bytes4(userOp.callData) == this.addOwner.selector;
        if (userOp.initCode.length != 0 && !isAddOwner) {
            // revert("wallet: not allow");
            return SIG_VALIDATION_FAILED;
        }

        if (!isAddOwner) {
            bytes32 hash = userOpHash.toEthSignedMessageHash();
            address signatureAddress = hash.recover(userOp.signature);
            if (owners[signatureAddress] <= 0) {
                return SIG_VALIDATION_FAILED;
            }
        }
        return 0;
    }

    // EIP-1271
    function isValidSignature(bytes32 _hash, bytes memory _signature) public view returns (bytes4 magicValue){
        bytes32 hash = _hash.toEthSignedMessageHash();
        require(owners[hash.recover(_signature)] > 0, "wallet: wrong signature");
        return MAGICVALUE;
    }

    /**
     * check current wallet deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * deposit more funds for this wallet in the entryPoint
     */
    function addDeposit() public payable {
        (bool req,) = address(entryPoint()).call{value : msg.value}("");
        require(req);
    }

    /**
     * withdraw value from the wallet's deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyAdmin {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    function approve(IERC20 token, address spender) external onlyAdmin {
        token.approve(spender, type(uint256).max);
    }
}


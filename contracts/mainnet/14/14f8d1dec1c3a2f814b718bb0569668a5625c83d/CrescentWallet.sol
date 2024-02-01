// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./BaseWallet.sol";
import "./Strings.sol";
import "./Address.sol";
import "./Context.sol";
import "./ECDSA.sol";
import "./IERC20.sol";
import "./Initializable.sol";
import "./DKIMManager.sol";
import "./UserOperation.sol";
import "./ICreate2Deployer.sol";
import "./StakeManager.sol";
import "./IPaymaster.sol";
import "./VerifierInfo.sol";

interface IVerifier{
    function verifier(
        address owner,
        bytes memory modulus,
        VerifierInfo calldata info
    ) external view returns (bool);
}

contract CrescentWallet is BaseWallet, Initializable {

    using ECDSA for bytes32;
    using UserOperationLib for UserOperation;
    bytes4 constant internal MAGICVALUE = 0x1626ba7e; // EIP-1271 magic value

    uint96 private _nonce;

    address[] private allOwner;
    mapping (address => uint16) private owners;

    address public dkimVerifier;

    DKIMManager private dkimManager;

    EntryPoint private _entryPoint;
    event EntryPointChanged(address indexed oldEntryPoint, address indexed newEntryPoint);

    constructor(){}

    function nonce() public view virtual override returns (uint256) {
        return _nonce;
    }

    function entryPoint() public view virtual override returns (EntryPoint) {
        return _entryPoint;
    }

    function initialize(address anEntryPoint, address dkim, address _dkimVerifier) external initializer {
        _entryPoint = EntryPoint(payable(anEntryPoint));
        dkimManager =  DKIMManager(payable(dkim));
        dkimVerifier = _dkimVerifier;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    modifier onlyAdmin() {
        _requireFromAdmin();
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
        bytes memory modulus = dkimManager.dkim(info.ds);
        require(modulus.length != 0, "Not find modulus!");
        require(IVerifier(dkimVerifier).verifier(owner, modulus, info), "Verification failed!");
        require(allOwner.length < type(uint16).max, "Too many owners");
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
        dest.transfer(amount);
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

    /**
     * change entry-point:
     * a wallet must have a method for replacing the entryPoint, in case the the entryPoint is
     * upgraded to a newer version.
     */
    function _updateEntryPoint(address newEntryPoint) internal override {
        emit EntryPointChanged(address(_entryPoint), newEntryPoint);
        _entryPoint = EntryPoint(payable(newEntryPoint));
    }

    /// implement template method of BaseWallet
    function _validateAndUpdateNonce(UserOperation calldata userOp) internal override {
        require(_nonce++ == userOp.nonce, "wallet: invalid nonce");
    }

    /// implement template method of BaseWallet
    function _validateSignature(UserOperation calldata userOp, bytes32 requestId) internal view override {
        //0x350bddaa addOwner
        bool isAddOwner = bytes4(userOp.callData) == 0x350bddaa;
        if (userOp.initCode.length != 0 && !isAddOwner) {
            revert("wallet: not allow");
        }

        if (!isAddOwner) {
            bytes32 hash = requestId.toEthSignedMessageHash();
            address signatureAddress = hash.recover(userOp.signature);
            require(owners[signatureAddress] > 0, "wallet: wrong signature");
        }
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


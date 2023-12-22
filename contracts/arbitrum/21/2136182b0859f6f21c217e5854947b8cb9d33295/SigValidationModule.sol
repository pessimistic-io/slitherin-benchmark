// SPDX-License-Identifier: LGPL-3.0-only

/// @title Module Interface - A contract that can pass messages to a Module Manager contract if enabled by that contract.
pragma solidity >=0.7.0 <0.9.0;

import "./IAvatar.sol";
import "./EIP712CrossChain.sol";
import "./IGnosisSafe.sol";
import "./IAvaultRouter.sol";
import "./IModule.sol";
import "./UserOperation.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./ECDSA.sol";
import "./IERC20.sol";


contract SigValidationModule is Ownable, EIP712CrossChain, IModule{
    using Counters for Counters.Counter;

    mapping(address => Counters.Counter) private _nonces;

    mapping(address => bool) public delegators;
    address public avaultRouter = address(0);
    address payable public feeAccount = payable(msg.sender);

    // solhint-disable-next-line var-name-mixedcase
    // bytes32 private immutable SAFE_MODULE_TX_TYPEHASH =
    //     keccak256("SafeModuleTx(uint256 toChainId,address to,uint256 value,bytes data,address gasToken,uint256 gasTokenAmount,uint8 operation,uint256 nonce)");
    bytes32 private constant SAFE_MODULE_TX_TYPEHASH = 0xeb641683a0ba2a6f28ce015e12640e8218e2f66c1632a517d438b1e3d87d3942;

    event DelegatorSet(address indexed _delegator, bool _isAuthed);
    event AvaultRouterSet(address _avaultRouter);

    constructor() EIP712CrossChain("Avault", "1"){}

    function setAvaultRouter(address _avaultRouter) external onlyOwner{
        avaultRouter = _avaultRouter;
        emit AvaultRouterSet(_avaultRouter);
    }

    function setDelegator(address _delegator, bool _auth) external onlyOwner {
        delegators[_delegator] = _auth;
        emit DelegatorSet(_delegator, _auth);
    }

    function setFeeAccount(address payable _feeAccount) external onlyOwner{
        feeAccount = _feeAccount;
    }

    /// @dev Passes a transaction to be executed by the avatar.
    /// @notice Can only be called by router or delegator.
    /// @param avatar user Safe address.
    /// @param srcAddress user's main account
    /// @param uo UserOperation
    function exec(
        address avatar,
        address srcAddress,
        UserOperation calldata uo
    ) external returns (bool success) {
        if(msg.sender == avaultRouter){
            //the safe address is trusted.
        }else if(delegators[msg.sender]){
            //should calculate the safe address locally.
            (address _computedAvatar,) = IAvaultRouter(avaultRouter).computeSafeAddress(srcAddress);
            require(_computedAvatar == avatar, "incorrect avatar");
        }else{
            revert("unauthed");
        }

        require(IGnosisSafe(avatar).isOwner(srcAddress), "not owner");
        require(IGnosisSafe(avatar).getThreshold() == 1, "not unique owner");
        require(getChainId() == uo.toChainId, "incorrect chain");
        /** todo filter the to address
        *  1. prevent fishing risk, the to shouldn't transfer asset to others
        *  2. the to shouldn't consume too many gas but dosn't have enough asset to pay
        *  3. gasToken should be valid
        **/

        //check signature
        bytes32 structHash = keccak256(abi.encode(SAFE_MODULE_TX_TYPEHASH, uo.toChainId, uo.to, uo.value, uo.data, uo.gasToken, uo.gasTokenAmount, uo.operation, _useNonce(avatar)));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, uo.v, uo.r, uo.s);
        require(signer == srcAddress, "invalid sig");

        //get fee
        if(uo.gasTokenAmount > 0){
            if (uo.gasToken == address(0)) {
                // native coin as gas fee (e.g. ETH, BNB)
                success = IAvatar(avatar).execTransactionFromModule(
                    feeAccount,
                    uo.gasTokenAmount,
                    "",
                    Enum.Operation.Call
                );
                require(success, "native payment failed");
            } else {
                success = IAvatar(avatar).execTransactionFromModule(
                    uo.gasToken,
                    0,
                    abi.encodeWithSelector(IERC20.transfer.selector, feeAccount, uo.gasTokenAmount),
                    Enum.Operation.Call
                );
                require(success, "token payment failed");
            }
        }

        success = IAvatar(avatar).execTransactionFromModule(
            uo.to,
            uo.value,
            uo.data,
            uo.operation
        );
        return success;
    }

     /**
     * @dev See {IERC20Permit-nonces}.
     */
    function nonces(address avatar) public view returns (uint256) {
        return _nonces[avatar].current();
    }

    /**
     * @dev See {IERC20Permit-DOMAIN_SEPARATOR}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev "Consume a nonce": return the current value and increment.
     *
     * _Available since v4.1._
     */
    function _useNonce(address _avatar) internal returns (uint256 current) {
        Counters.Counter storage nonce = _nonces[_avatar];
        current = nonce.current();
        nonce.increment();
    }

    /// @dev Returns the chain id used by this contract.
    function getChainId() public view returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }
}


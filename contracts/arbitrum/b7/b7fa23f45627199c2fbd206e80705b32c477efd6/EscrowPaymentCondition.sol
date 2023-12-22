pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import "./Reward.sol";
import "./Common.sol";
import "./ConditionStoreLibrary.sol";
import "./DIDRegistry.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IDynamicPricing.sol";

/**
 * @title Escrow Payment Condition
 * @author Nevermined
 *
 * @dev Implementation of the Escrow Payment Condition
 *
 *      The Escrow payment is reward condition in which only 
 *      can release reward if lock and release conditions
 *      are fulfilled.
 */
contract EscrowPaymentCondition is Reward, ReentrancyGuardUpgradeable {

    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 constant public CONDITION_TYPE = keccak256('EscrowPayment');
    bytes32 constant public USED_PAYMENT_ID = keccak256('UsedPayment');

    event Fulfilled(
        bytes32 indexed _agreementId,
        address indexed _tokenAddress,
        address[] _receivers,
        bytes32 _conditionId,
        uint256[] _amounts
    );

    event Received(
        address indexed _from, 
        uint _value
    );
    
    receive() external payable {
        emit Received(_msgSender(), msg.value);
    }

    /**
     * @notice initialize init the 
     *       contract with the following parameters
     * @param _owner contract's owner account address
     * @param _conditionStoreManagerAddress condition store manager address
     */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress
    )
    external
    initializer()
    {
        require(
            _conditionStoreManagerAddress != address(0),
            'Invalid address'
        );
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );
    }

    /**
     * @notice hashValues generates the hash of condition inputs 
     *        with the following parameters
     * @param _did asset decentralized identifier               
     * @param _amounts token amounts to be locked/released
     * @param _receivers receiver's addresses
     * @param _lockPaymentAddress lock payment contract address
     * @param _tokenAddress the ERC20 contract address to use during the payment 
     * @param _lockCondition lock condition identifier
     * @param _releaseConditions release condition identifier
     * @return bytes32 hash of all these values 
     */
    function hashValuesMulti(
        bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _returnAddress,
        address _lockPaymentAddress,
        address _tokenAddress,
        bytes32 _lockCondition,
        bytes32[] memory _releaseConditions
    )
    public pure
    returns (bytes32)
    {
        require(
            _amounts.length == _receivers.length,
            'Amounts and Receivers arguments have wrong length'
        );
        return keccak256(
            abi.encode(
                _did,
                _amounts,
                _receivers,
                _returnAddress,
                _lockPaymentAddress, 
                _tokenAddress,
                _lockCondition,
                _releaseConditions
            )
        );
    }
    
    function encodeParams(
        bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _returnAddress,
        address _lockPaymentAddress,
        address _tokenAddress,
        bytes32 _lockCondition,
        bytes32[] memory _releaseConditions
    )
    public pure
    returns (bytes memory)
    {
        require(
            _amounts.length == _receivers.length,
            'Amounts and Receivers arguments have wrong length'
        );
        return abi.encode(
            _did,
            _amounts,
            _receivers,
            _returnAddress,
            _lockPaymentAddress, 
            _tokenAddress,
            _lockCondition,
            _releaseConditions
        );
    }
    
    function hashValues(
        bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _returnAddress,
        address _lockPaymentAddress,
        address _tokenAddress,
        bytes32 _lockCondition,
        bytes32 _releaseCondition
    )
    public pure
    returns (bytes32)
    {
        bytes32[] memory _releaseConditions = new bytes32[](1);
        _releaseConditions[0] = _releaseCondition;
        return hashValuesMulti(_did, _amounts, _receivers, _returnAddress, _lockPaymentAddress, _tokenAddress, _lockCondition, _releaseConditions);
    }
    
   /**
    * @notice hashValuesLockPayment generates the hash of condition inputs 
    *        with the following parameters
    * @param _did the asset decentralized identifier 
    * @param _rewardAddress the contract address where the reward is locked       
    * @param _tokenAddress the ERC20 contract address to use during the lock payment. 
    *        If the address is 0x0 means we won't use a ERC20 but ETH for payment     
    * @param _amounts token amounts to be locked/released
    * @param _receivers receiver's addresses
    * @return bytes32 hash of all these values 
    */
    function hashValuesLockPayment(
        bytes32 _did,
        address _rewardAddress,
        address _tokenAddress,
        uint256[] memory _amounts,
        address[] memory _receivers
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(
            _did,
            _rewardAddress,
            _tokenAddress,
            _amounts,
            _receivers
        ));
    }

    /**
     * @notice fulfill escrow reward condition
     * @dev fulfill method checks whether the lock and 
     *      release conditions are fulfilled in order to 
     *      release/refund the reward to receiver/sender 
     *      respectively.
     * @param _agreementId agreement identifier
     * @param _did asset decentralized identifier          
     * @param _amounts token amounts to be locked/released
     * @param _receivers receiver's address
     * @param _lockPaymentAddress lock payment contract address
     * @param _tokenAddress the ERC20 contract address to use during the payment
     * @param _lockCondition lock condition identifier
     * @param _releaseConditions release condition identifier
     * @return condition state (Fulfilled/Aborted)
     */
    function fulfillMulti(
        bytes32 _agreementId,
        bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _returnAddress,
        address _lockPaymentAddress,
        address _tokenAddress,
        bytes32 _lockCondition,
        bytes32[] memory _releaseConditions
    )
    public
    nonReentrant
    returns (ConditionStoreLibrary.ConditionState)
        {
        return fulfillKludge(Args(_agreementId,
        _did,
         _amounts,
         _receivers,
         _returnAddress,
         _lockPaymentAddress,
         _tokenAddress,
         _lockCondition,
         _releaseConditions));
    }

    struct Args {
        bytes32 _agreementId;
        bytes32 _did;
        uint256[] _amounts;
        address[] _receivers;
        address _returnAddress;
        address _lockPaymentAddress;
        address _tokenAddress;
        bytes32 _lockCondition;
        bytes32[] _releaseConditions;
    }

    function fulfillKludge(Args memory a)
    internal
    returns (ConditionStoreLibrary.ConditionState)
    {

        require(keccak256(
            abi.encode(
                a._agreementId,
                conditionStoreManager.getConditionTypeRef(a._lockCondition),
                hashValuesLockPayment(a._did, a._lockPaymentAddress, a._tokenAddress, a._amounts, a._receivers)
            )
        ) == a._lockCondition,
            'LockCondition ID does not match'
        );
        
        require(
            conditionStoreManager.getConditionState(a._lockCondition) ==
            ConditionStoreLibrary.ConditionState.Fulfilled,
            'LockCondition needs to be Fulfilled'
        );

        bool allFulfilled = true;
        bool someAborted = false;
        for (uint i = 0; i < a._releaseConditions.length; i++) {
            ConditionStoreLibrary.ConditionState cur = conditionStoreManager.getConditionState(a._releaseConditions[i]);
            if (cur != ConditionStoreLibrary.ConditionState.Fulfilled) {
                allFulfilled = false;
            }
            if (cur == ConditionStoreLibrary.ConditionState.Aborted) {
                someAborted = true;
            }
        }

        require(someAborted || allFulfilled, 'Release conditions unresolved');

        bytes32 id = generateId(
            a._agreementId,
            hashValuesMulti(
                a._did,
                a._amounts,
                a._receivers,
                a._returnAddress,
                a._lockPaymentAddress,
                a._tokenAddress,
                a._lockCondition,
                a._releaseConditions
            )
        );        
        
        ConditionStoreLibrary.ConditionState state;
        if (allFulfilled) {
            if (a._tokenAddress != address(0))
                state = _transferAndFulfillERC20(id, a._tokenAddress, a._receivers, a._amounts, a._did);
            else
                state = _transferAndFulfillETH(id, a._receivers, a._amounts, a._did);
            
            emit Fulfilled(a._agreementId, a._tokenAddress, a._receivers, id, a._amounts);

        } else if (someAborted) {
            uint256[] memory _totalAmounts = new uint256[](1);
            _totalAmounts[0] = calculateTotalAmount(a._amounts);
            address[] memory _originalSender = new address[](1);
            _originalSender[0] = a._returnAddress;
            
            if (a._tokenAddress != address(0))
                state = _transferAndFulfillERC20(id, a._tokenAddress, _originalSender, _totalAmounts, a._did);
            else
                state = _transferAndFulfillETH(id, _originalSender, _totalAmounts, a._did);
            
            emit Fulfilled(a._agreementId, a._tokenAddress, _originalSender, id, _totalAmounts);
            
        }

        return state;
    }

    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _returnAddress,
        address _lockPaymentAddress,
        address _tokenAddress,
        bytes32 _lockCondition,
        bytes32 _releaseCondition
    )
    external
    returns (ConditionStoreLibrary.ConditionState)
    {
        bytes32[] memory _releaseConditions = new bytes32[](1);
        _releaseConditions[0] = _releaseCondition;
        return fulfillMulti(_agreementId, _did, _amounts, _receivers, _returnAddress, _lockPaymentAddress, _tokenAddress, _lockCondition, _releaseConditions);
    }
    
    
    /**
    * @notice _transferAndFulfill transfer ERC20 tokens and 
    *       fulfill the condition
    * @param _id condition identifier
    * @param _tokenAddress the ERC20 contract address to use during the payment    
    * @param _receivers receiver's address
    * @param _amounts token amount to be locked/released
    * @return condition state (Fulfilled/Aborted)
    */
    function _transferAndFulfillERC20(
        bytes32 _id,
        address _tokenAddress,
        address[] memory _receivers,
        uint256[] memory _amounts,
        bytes32 _did
    )
    private
    returns (ConditionStoreLibrary.ConditionState)
    {
        
        IERC20Upgradeable token = ERC20Upgradeable(_tokenAddress);
        
        for(uint i = 0; i < _receivers.length; i++)    {
            require(
                _receivers[i] != address(this),
                'Escrow contract can not be a receiver'
            );
            token.safeTransfer(_receivers[i], _amounts[i]);
        }

        return super.fulfillWithProvenance(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled,
            _did,
            'EscrowPaymentCondition',
            _msgSender()
        );
    }

    /**
    * @notice _transferAndFulfill transfer ETH and 
    *       fulfill the condition
    * @param _id condition identifier
    * @param _receivers receiver's address
    * @param _amounts token amount to be locked/released
    * @return condition state (Fulfilled/Aborted)
    */
    function _transferAndFulfillETH(
        bytes32 _id,
        address[] memory _receivers,
        uint256[] memory _amounts,
        bytes32 _did
    )
    private
    returns (ConditionStoreLibrary.ConditionState)
    {
        for(uint i = 0; i < _receivers.length; i++)    {
            require(
                _receivers[i] != address(this),
                'Escrow contract can not be a receiver'
            );
            
            require(
                address(this).balance >= _amounts[i],
                'Contract balance too low'
            );
            
            // solhint-disable-next-line
            (bool sent,) = _receivers[i].call{value: _amounts[i]}('');
            require(sent, 'Failed to send Ether');
        }

        return super.fulfillWithProvenance(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled,
            _did,
            'EscrowPaymentCondition',
            _msgSender()
        );
    }    
    
}


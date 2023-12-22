//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeMathUpgradeable.sol";


library Structs {
    struct ReservedAmount {
        uint256 amount;
        uint256 reserved;
        bool isPresent;
    }
    struct Treasuries {
        uint256 amount;
        address treasury;
    }
}

interface IProxyRouter {
    function treasuries(uint256 _index)
        external
        view
        returns (Structs.Treasuries memory);

    function getTreasuriesLength() external view returns (uint256);
}

contract GamesPoolUpgradeable is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    mapping(address => Structs.ReservedAmount) public reservedAmount;
    IProxyRouter public rootCaller;
    address[] public keyListReservedAmount;

    // Events
    event Payout(address to, uint256 amount);
    event PayoutFailed(address to, uint256 amount);
    event AmountIsTooBigForToReserved();
    event Credited(address user, uint amount);
    event CreditedReservedAmount(address user, address _address, uint amount);
    modifier onlyOwnerOrRootCallerAccount() {
        require(
            owner() == _msgSender() ||
                (_msgSender() == address(rootCaller) && address(rootCaller) != address(0)),
            "Ownable: caller is not the owner or rootCaller"
        );
        _;
    }

    modifier onlyReservedAmountAccount() {
        require(
            reservedAmount[_msgSender()].isPresent,
            "Ownable: only reservedAmount account"
        );
        _;
    }

    /** @dev initializes contract
     * @param _rootCaller rootCaller address.
     */
    function initialize(
        address _rootCaller
    ) public payable initializer {
        rootCaller = IProxyRouter(_rootCaller);
        __Ownable_init();
    }

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /** @dev adding amount to pool. Only reserved account.
     * @param _toReserve reserving amount
     */
    function depositReservedAmount(uint256 _toReserve)
        public
        payable
        onlyReservedAmountAccount
    {
        reservedAmount[msg.sender].amount += msg.value;
        reservedAmount[msg.sender].reserved += _toReserve;        
    }

    /** @dev withdraw amount from pool. Only reserved account.
     * @param _amount amount to withdraw
     * @param _toReserve reserving amount to delete
     * @param _address where to withdraw
     */
    function withdrawReservedAmount(uint256 _amount, uint256 _toReserve, address _address)
        public
        onlyReservedAmountAccount returns(bool)
    {
        if (_amount > 0){
            (bool __bool, ) = SafeMathUpgradeable.trySub(
                reservedAmount[msg.sender].amount,
                _amount
            );
            if (__bool) {
                reservedAmount[msg.sender].amount -= _amount;
                (bool success, ) = _address.call{value: _amount}("");
                if (success) {
                    emit Payout(_address, _amount);
                } else {
                    emit PayoutFailed(_address, _amount);
                }
            } else {
                emit AmountIsTooBigForToReserved();
            }
            
        }
        (bool _bool, ) = SafeMathUpgradeable.trySub(
            reservedAmount[msg.sender].reserved,
            _toReserve
        );
        if (_bool) {
            reservedAmount[msg.sender].reserved -= _toReserve;
            return true;
        } else {
            emit AmountIsTooBigForToReserved();
            return false;
        }
    }

    /** @dev creating reservedAmount object for address
     * @param _address *
     */
    function setInitReservedAmount(address _address)
        public
        onlyOwnerOrRootCallerAccount
    {
        require(
            !reservedAmount[_address].isPresent,
            "That address is already present"
        );
        reservedAmount[_address] = Structs.ReservedAmount({
            amount: 0,
            isPresent: true,
            reserved: 0
        });
        keyListReservedAmount.push(_address);
    }

    /** @dev deleting reservedAmount object
     * @param _address *
     */
    function deleteReservedAmount(address _address)
        public
        onlyOwnerOrRootCallerAccount
    {
        delete reservedAmount[_address];
        for (uint256 i = 0; i < keyListReservedAmount.length; i++) {
            if (
                keccak256(abi.encodePacked(keyListReservedAmount[i])) ==
                keccak256(abi.encodePacked(_address))
            ) {
                keyListReservedAmount[i] = keyListReservedAmount[
                    keyListReservedAmount.length - 1
                ];
                keyListReservedAmount.pop();
            }
        }
    }
    
    /** @dev adding value for reservedAmount object
     * @param _address *
     */
    function depositInReservedAmount(address _address) public payable {
        require(
            reservedAmount[_address].isPresent,
            "That address is not present"
        );
        reservedAmount[_address].amount += msg.value;
        emit CreditedReservedAmount(msg.sender, _address, msg.value);
    }

    /** @dev updates contract rootCaller
     * @param _newRootCaller *
     */
    function setNewRootCaller(address _newRootCaller) public onlyOwner {
        rootCaller = IProxyRouter(_newRootCaller);
    }

    /** @dev withdrawing amount from contract
     * @param _amount *
     */
    function withdraw(uint _amount) public onlyOwner {
        uint balance = address(this).balance;

        require(_amount <= balance, "amount should be less than balance");

        (bool success, ) = msg.sender.call{value : _amount}("");
        require(success, "Transfer failed.");

        emit Payout(msg.sender, _amount);
    }

    receive() external payable {
        emit Credited(msg.sender, msg.value);
    }
}


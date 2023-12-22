// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VRFCoordinatorV2Interface.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";

interface IRNG {
    function makeRequestUint256() external returns (bytes32);
    function makeRequestUint256Array(uint256 size) external returns (bytes32);
}

interface IGamesPool {
    function reservedAmount(address _address)
        external
        view
        returns (MainStructs.ReservedAmount memory);

    function depositReservedAmount(uint256 _toReserve) external payable;

    function withdrawReservedAmount(
        uint256 _amount,
        uint256 _toReserve,
        address _address
    ) external returns (bool);
}

interface IRootCaller {
    function gamesPoolContract() external view returns (address);
}

library MainStructs {
    struct ReservedAmount {
        uint256 amount;
        uint256 reserved;
        bool isPresent;
    }
}

abstract contract GameUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    error RNGUnauthorized(address _caller);

    uint64 public minBetAmount;
    uint64 public maxBetAmount;
    uint256 public maxPayout;
    address public rootCaller;
    IGamesPool public gamesPoolContract;
    IRNG public rng;

    event GamePayoutFailed(
        address indexed user,
        uint256 payoutAmount,
        uint256 indexed txIdentifier
    );

    event Credited(address user, uint256 amount);
    event Debited(address user, uint256 amount);

    modifier onlyOwnerOrRootCallerAccount() {
        require(
            owner() == _msgSender() ||
                (_msgSender() == rootCaller && rootCaller != address(0)),
            "Ownable: caller is not the owner or rootCaller"
        );
        _;
    }

    modifier onlyRNG() {
        if (msg.sender != address(rng)) {
            revert RNGUnauthorized(msg.sender);
        }
        _;
    }

    /** @dev Creates a contract.
    * @param _rootCaller Root caller of that contract.
    * @param _rng the callback contract
    */
    function initialize_(
        address _rng,
        address _rootCaller
    ) public payable initializer {
        rng = IRNG(_rng);
        __Ownable_init();
        minBetAmount = 0.01 ether;
        maxBetAmount = 0.5 ether;
        maxPayout = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        rootCaller = _rootCaller;
        bool success = is_contract(_rootCaller);
        if (success) {
            IRootCaller rootCallerContract = IRootCaller(
                    _rootCaller
                );
            gamesPoolContract = IGamesPool(
                rootCallerContract.gamesPoolContract()
            );
        }
    }

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /** @dev Function to withdraw BNB from contract.
     * @param _amount in gwei
     */
    function withdraw(uint256 _amount) public onlyOwner {
        uint256 balance = address(this).balance;

        require(_amount <= balance, "amount should be less than balance");

        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed.");

        emit Debited(msg.sender, _amount);
    }

    /** @dev Function to update minBetAmount
     * @param _minBetAmount New minBetAmount
     */
    function updateMinBetAmount(uint64 _minBetAmount) public onlyOwner {
        minBetAmount = _minBetAmount;
    }

    /** @dev Function to update maxBetAmount
     * @param _maxBetAmount New maxBetAmount
     */

    function updateMaxBetAmount(uint64 _maxBetAmount) public onlyOwner {
        maxBetAmount = _maxBetAmount;
    }

    function setNewRootCaller(address _newRootCaller) public onlyOwner {
        IRootCaller rootCallerContract = IRootCaller(
                _newRootCaller
            );
        gamesPoolContract = IGamesPool(
            rootCallerContract.gamesPoolContract()
        );
        rootCaller = _newRootCaller;
    }

    /** @dev Function to update maxPayout
     * @param _maxPayout New maxPayout
     */
    function updateMaxPayout(uint64 _maxPayout) public onlyOwner {
        maxPayout = _maxPayout;
    }

    function setNewRNG(address _rng) public onlyOwner {
        rng = IRNG(_rng);
    }

    function is_contract(address _addr)
        internal
        view
        returns (bool _isContract)
    {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    receive() external payable {
        emit Credited(msg.sender, msg.value);
    }
}


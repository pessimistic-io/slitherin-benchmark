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

interface IProxyRouter {
    function gasPerRoll() external view returns (uint256);
}


abstract contract GameFreeWheelUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    error RNGUnauthorized(address _caller);

    address public rootCaller;
    IRNG public rng;

    modifier onlyOwnerOrRootCallerAccount() {
        require(
            owner() == _msgSender() ||
                (_msgSender() == rootCaller && rootCaller != address(0)),
            "Ownable: caller is not the owner or rootCaller"
        );
        _;
    }

    event GamePayoutFailed(
        address indexed user,
        uint256 payoutAmount,
        uint256 indexed txIdentifier
    );

    event Credited(address user, uint256 amount);
    event Debited(address user, uint256 amount);

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
        rootCaller = _rootCaller;
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

    function setNewRootCaller(address _newRootCaller) public onlyOwner {
        rootCaller = _newRootCaller;
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


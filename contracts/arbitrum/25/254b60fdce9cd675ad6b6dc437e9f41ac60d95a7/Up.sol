// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./Updoge.sol";
import "./BalancerManager.sol";
import "./Math.sol";

contract Up is Ownable, AccessControl {
    // IERC20 private immutable WETH =
    //     IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 private immutable WETH =
        IERC20(0x5979D7b546E38E414F7E9822514be443A4800529);
    bytes32 public constant UPPER_ROLE = keccak256("UPPER_ROLE");

    uint256 public burnRatePerDay;
    uint256 public buyRate;
    uint256 public lastUppedAt;
    address public protocolTreasuryAddress;

    BalancerManager public balancerManager;
    Updoge public updoge;

    event BurnRatePerDayChanged(uint256 burnRatePerDay);
    event BuyRateChanged(uint256 buyRate);

    modifier onlyUpper() {
        require(hasRole(UPPER_ROLE, _msgSender()), "Address is not upper");
        _;
    }

    constructor(
        Updoge updoge_,
        BalancerManager balancerManager_,
        address protocolTreasuryAddress_
    ) {
        updoge = updoge_;
        balancerManager = balancerManager_;
        protocolTreasuryAddress = protocolTreasuryAddress_;

        lastUppedAt = block.timestamp;

        WETH.approve(
            address(balancerManager),
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        setBuyRate(1 ether);
        setBurnRatePerDay(0.02 ether);
    }

    receive() external payable {}

    function up(uint256 timestamp_) public onlyUpper {
        uint256 timestamp = timestamp_ == 0 ? block.timestamp : timestamp_;

        require(
            timestamp > lastUppedAt,
            "No time has passed since last leg up"
        );

        require(
            timestamp <= block.timestamp,
            "Can't be bigger than block.timestamp"
        );

        uint256 secondsPassed = timestamp - lastUppedAt;
        lastUppedAt = timestamp;

        uint256 lpAmountToRemove = calculateLpAmountToRemoveBasedOnSecondsPassed(
                balancerManager.poolBalance(),
                burnRatePerDay,
                secondsPassed
            );

        require(lpAmountToRemove != 0, "No liquidity to remove");

        // Exit pool proportionally with WETH-UPDOGE
        balancerManager.exitPool(lpAmountToRemove);

        // Buy UPDOGE with WETH
        balancerManager.buyUpdoge(
            (WETH.balanceOf(address(this)) * buyRate) / 1 ether,
            0.1 ether
        );

        // Transfer the rest of WETH to treasury
        WETH.transfer(protocolTreasuryAddress, WETH.balanceOf(address(this)));

        // Burn withdrawn+bought UPDOGE
        updoge.burn(updoge.balanceOf(address(this)));
    }

    function grantUpper(address address_) external onlyOwner {
        grantRole(UPPER_ROLE, address_);
    }

    function revokeUpper(address address_) external onlyOwner {
        revokeRole(UPPER_ROLE, address_);
    }

    function setBurnRatePerDay(uint256 burnRatePerDay_) public onlyOwner {
        require(burnRatePerDay_ != 0, "burnRatePerDay can't be zero");
        require(
            burnRatePerDay_ <= 1 ether,
            "burnRatePerDay can't be more than 100%"
        );

        burnRatePerDay = burnRatePerDay_;

        emit BurnRatePerDayChanged(burnRatePerDay);
    }

    function setBuyRate(uint256 buyRate_) public onlyOwner {
        require(buyRate_ != 0, "buyRate can't be zero");
        require(buyRate_ <= 1 ether, "buyRate can't be more than 100%");

        buyRate = buyRate_;

        emit BuyRateChanged(buyRate);
    }

    function setProtocolTreasuryAddress(
        address protocolTreasuryAddress_
    ) public onlyOwner {
        protocolTreasuryAddress = protocolTreasuryAddress_;
    }

    function calculateLpAmountToRemoveBasedOnSecondsPassed(
        uint256 lpAmount_,
        uint256 burnRatePerDay_,
        uint256 secondsPassed_
    ) public pure returns (uint256) {
        return
            (lpAmount_ * secondsPassed_ * burnRatePerDay_) / (1 ether * 1 days);
    }
}


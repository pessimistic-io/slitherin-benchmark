// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Initializable } from "./Initializable.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IPresaleUpgradeable } from "./IPresaleUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { IAggregatorV3, PresaleOracleUpgradeable } from "./PresaleOracleUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { SafeTransferLib } from "./SafeTransfer.sol";

contract PresaleArbUpgradeable is
    IPresaleUpgradeable,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PresaleOracleUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint96 constant HUNDER_PERCENT_IN_BPS = 10_000;

    address public beneficiary;
    uint256 public tokenPrice;
    uint256 public minPurchase;
    uint256 public tokensSold;
    mapping(address => uint256) public contributions; // user => bought tokens

    receive() external payable {}

    fallback() external payable {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
        beneficiary = 0x463Bb1a0fd22acA09E87705daDdAF00FB3a91539;
        minPurchase = 10 ether;
        tokenPrice = 0.1 ether;

        _setPriceFeeds(
            address(0),
            PriceFeed({
                usdAggregator: IAggregatorV3(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
                multiplier: 1 ether,
                price: 0
            })
        );
        _setPriceFeeds(
            0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
            PriceFeed({
                usdAggregator: IAggregatorV3(0x0000000000000000000000000000000000000000),
                multiplier: 1000000,
                price: 1 ether
            })
        );
    }

    // CONFIG
    function setMinPursechase(uint256 minPurchase_) external onlyOwner {
        require(minPurchase_ > 0, "!Price");
        minPurchase = minPurchase_;
        emit SetMinPurchase(minPurchase_);
    }

    function setTokenPrice(uint256 newPrice_) external onlyOwner {
        require(newPrice_ > 0, "!Price");
        tokenPrice = newPrice_;
        emit SetPrice(newPrice_);
    }

    function setBeneficiary(address beneficiary_) external onlyOwner {
        require(beneficiary_ != address(0), "!Address");
        beneficiary = beneficiary_;
        emit SetBeneficiary(beneficiary_);
    }

    function setPriceFeeds(address token_, PriceFeed calldata priceFeed_) external onlyOwner {
        _setPriceFeeds(token_, priceFeed_);
    }

    function updateFromOrtherNetwork(address[] calldata users_) external onlyOwner {
        uint256 length = users_.length;
        for (uint256 i = 0; i < length; ) {
            contributions[users_[i]] = 0;

            unchecked {
                ++i;
            }
        }
        tokensSold = 0;
    }

    // BUY PROCESSING
    function buy(address paymentToken_, uint256 paymentAmount_, bool) external payable nonReentrant {
        address sender = _msgSender();
        uint256 usdAmount = _getUsdAmount(paymentToken_, paymentAmount_);

        require(usdAmount >= minPurchase, "Min");

        uint256 tokenAmount = _getTokenPresaleAmount(usdAmount);

        _receiveToken(paymentToken_, sender, paymentAmount_);
        tokensSold += tokenAmount;
        contributions[sender] += tokenAmount;

        emit TokensPurchased(sender, beneficiary, paymentToken_, paymentAmount_, tokenAmount);
    }

    function buyExactTokens(address paymentToken_, uint256 tokenAmount_, bool) external payable nonReentrant {
        address sender = _msgSender();

        uint256 usdAmount = _getTokenPresalePrice(tokenAmount_);
        require(usdAmount >= minPurchase, "Min");

        uint256 paymentAmount = _getTokenUsdAmount(paymentToken_, usdAmount);
        _receiveToken(paymentToken_, sender, paymentAmount);
        tokensSold += tokenAmount_;
        contributions[sender] += tokenAmount_;

        emit TokensPurchased(sender, beneficiary, paymentToken_, paymentAmount, tokenAmount_);
    }

    function rescue(address token_, uint256 amount_) external onlyOwner {
        if (token_ == address(0)) {
            SafeTransferLib.safeTransferETH(msg.sender, amount_);
        } else {
            SafeTransferLib.safeTransfer(token_, msg.sender, amount_);
        }
    }

    function _receiveToken(address token_, address from_, uint256 amount_) internal {
        if (token_ == address(0)) {
            require(msg.value >= amount_, "!Balance");
            SafeTransferLib.safeTransferETH(beneficiary, amount_);
        } else {
            SafeTransferLib.safeTransferFrom(token_, from_, beneficiary, amount_);
        }
    }

    // VIEW

    function getAccountInfoBSC(address account_) public view returns (uint256 contribution, uint256 totalSold) {
        return (contributions[account_], tokensSold);
    }

    function getTokenPresaleAmount(address paymentToken, uint256 paymentAmount) external view returns (uint256) {
        uint256 usdAmount = _getUsdAmount(paymentToken, paymentAmount);
        uint256 tokenAmount = _getTokenPresaleAmount(usdAmount);
        return tokenAmount;
    }

    function getTokenPresalePrice(address paymentToken, uint256 tokenReceiveAmount) external view returns (uint256) {
        uint256 usdAmount = _getTokenPresalePrice(tokenReceiveAmount);
        uint256 paymentAmount = _getTokenUsdAmount(paymentToken, usdAmount);
        return paymentAmount;
    }

    function _getTokenPresaleAmount(uint256 usdAmount) private view returns (uint256) {
        return (usdAmount * 1 ether) / tokenPrice;
    }

    function _getTokenPresalePrice(uint256 tokenAmount) private view returns (uint256) {
        return (tokenAmount * tokenPrice) / 1 ether;
    }

    /* solhint-disable no-empty-blocks */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}


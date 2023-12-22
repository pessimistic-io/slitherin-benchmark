// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IPaymentsReceiver, PriceType} from "./IPaymentsReceiver.sol";
import {IPayments} from "./IPayments.sol";
import {GoodEarthFacet} from "./GoodEarthFacet.sol";
import {LibMeta} from "./GoodEarthLibMeta.sol";
import {LibToken} from "./LibToken.sol";
import {WithStorage, WithModifiers, TokensConstants} from "./GoodEarthAppStorage.sol";
import {PaymentType} from "./IPayments.sol";
import {IERC20} from "./IERC20.sol";
import {LibDiamond} from "./LibDiamond.sol";
import {console} from "./console.sol";

contract BattlePassFacet is IPaymentsReceiver, WithModifiers {
    event BattlePassPurchased (
        address indexed account,
        uint256 indexed season,
        uint256 indexed price,
        uint8 paymentType
    );

    /**
     * @inheritdoc IPaymentsReceiver
     */
    function acceptERC20(
        address _payor, // payment sender
        address _paymentERC20, // address of token paid, either magic or ARB
        uint256 _paymentAmount, // amount of token sent, in absolute terms
        uint256 _paymentAmountInPricedToken, // paymentAmount (value in USD) * 10**8
        PriceType _priceType, // Always will be USD in our case
        address _pricedERC20 // won't be used in our case
    ) external onlySpellcasterPayments {
        emit PaymentReceived(
            _payor,
            _paymentERC20,
            _paymentAmount,
            _paymentAmountInPricedToken,
            _priceType,
            _pricedERC20
        );

        if (_priceType == PriceType.STATIC) {
            revert LibMeta.PaymentTypeNotAccepted('STATIC');
        } else if (_priceType == PriceType.PRICED_IN_ERC20) {
            revert LibMeta.PaymentTypeNotAccepted('PRICED_IN_ERC20');
        } else if (_priceType == PriceType.PRICED_IN_GAS_TOKEN) {
            revert LibMeta.PaymentTypeNotAccepted('PRICED_IN_GAS_TOKEN');
        }

        if (_paymentERC20 == getMagicTokenAddress()) {
            _acceptMagicPaymentPricedInUSD(
                _payor,
                _paymentAmount,
                _paymentAmountInPricedToken
            );
        } else if (_paymentERC20 == getArbTokenAddress()) {
            _acceptArbPaymentPricedInUSD(
                _payor,
                _paymentAmount,
                _paymentAmountInPricedToken
            );
        } else {
            revert LibMeta.PaymentTypeNotAccepted('UNSUPPORTED_TOKEN');
        }
    }

    function acceptGasToken(
        address _payor, // sender
        uint256 _paymentAmount, // amount of eth sent (dynamic)
        uint256 _paymentAmountInPricedToken, // paymentAmount * decimals in USD (10**8) (enum)
        PriceType _priceType, // will always be PRICED_IN_USD
        address _pricedERC20 // won't be used in our case
    ) external payable onlySpellcasterPayments {
        emit PaymentReceived(
            _payor,
            address(0),
            _paymentAmount,
            _paymentAmountInPricedToken,
            _priceType,
            _pricedERC20
        );
        if (msg.value != _paymentAmount) {
            revert LibMeta.IncorrectPaymentAmount(
                msg.value,
                _paymentAmountInPricedToken
            );
        }

        if (_priceType == PriceType.STATIC) {
            revert LibMeta.PaymentTypeNotAccepted('STATIC');
        } else if (_priceType == PriceType.PRICED_IN_ERC20) {
            revert LibMeta.PaymentTypeNotAccepted('PRICED_IN_ERC20');
        } else if (_priceType == PriceType.PRICED_IN_GAS_TOKEN) {
            revert LibMeta.PaymentTypeNotAccepted('PRICED_IN_GAS_TOKEN');
        } else {
            // priced in USD - good
            _acceptGasTokenPaymentPricedInUSD(
                _payor,
                _paymentAmount,
                _paymentAmountInPricedToken
            );
        }
    }

    function _acceptGasTokenPaymentPricedInUSD(
        address _payor,
        uint256 _paymentAmountInEth,
        uint256 _paymentAmountInUSD
    ) internal {
        _purchaseBattlePass(
            _payor,
            _paymentAmountInUSD,
            _paymentAmountInEth,
            PaymentType.ETH_IN_USD
        );
    }

    function _acceptMagicPaymentPricedInUSD(
        address _payor,
        uint256 _paymentAmountInMagic,
        uint256 _paymentAmountInUSD
    ) internal {
        _purchaseBattlePass(
            _payor,
            _paymentAmountInUSD,
            _paymentAmountInMagic,
            PaymentType.MAGIC_IN_USD
        );
    }

    function _acceptArbPaymentPricedInUSD(
        address _payor,
        uint256 _paymentAmountInArb,
        uint256 _paymentAmountInUSD
    ) internal {
        _purchaseBattlePass(
            _payor,
            _paymentAmountInUSD,
            _paymentAmountInArb,
            PaymentType.ARB_IN_USD
        );
    }

    function _purchaseBattlePass(
        address _payor,
        uint256 _paymentAmountInUSD,
        uint256 _paymentAmountInToken,
        PaymentType _paymentType
    ) internal {
        if (
            _paymentType == PaymentType.ETH_IN_USD &&
            msg.value != _paymentAmountInToken
        ) {
            revert LibMeta.IncorrectPaymentAmount(
                msg.value,
                _paymentAmountInToken
            );
        }

        uint256 battlePassUsdPrice = getBattlePassUsdPrice();
        if (battlePassUsdPrice != _paymentAmountInUSD) {
            revert LibMeta.IncorrectPaymentAmount(
                _paymentAmountInUSD,
                battlePassUsdPrice
            );
        }

        if (!_token().battlePassIsOpen) {
            revert LibMeta.NoActiveBattlePass();
        }

        uint8 currentBattlePassSeason = getCurrentBattlePassSeason();
        if (_token().battlePassSeasonClaimed[_payor] == currentBattlePassSeason) {
            revert LibMeta.BattlePassAlreadyClaimed();
        }

        _token().battlePassSeasonClaimed[_payor] = currentBattlePassSeason;
        emit BattlePassPurchased(
            _payor,
            currentBattlePassSeason,
            _paymentAmountInUSD,
            uint8(_paymentType)
        );
    }

    modifier onlySpellcasterPayments() {
        if (LibMeta._msgSender() != address(_constants().spellcasterPayments)) {
            revert LibMeta.SenderNotSpellcasterPayments(LibMeta._msgSender());
        }
        _;
    }

    function getSpellcasterAddress() external view returns (address) {
        return address(_constants().spellcasterPayments);
    }

    function setSpellcasterAddress(
        address spellcasterAddress_
    ) external ownerOnly {
        _constants().spellcasterPayments = IPayments(spellcasterAddress_);
    }

    function withdrawETH() public ownerOnly {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        payable(ds.contractOwner).transfer(address(this).balance);
    }

    function withdrawERC20(address tokenAddress, address to) public ownerOnly {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, 'No tokens to withdraw');
        token.transfer(to, balance);
    }

    function getMagicTokenAddress() public view returns (address) {
        return _constants().magicTokenAddress;
    }

    function setMagicTokenAddress(address magicTokenAddress_) public ownerOnly {
        _constants().magicTokenAddress = magicTokenAddress_;
    }

    function getArbTokenAddress() public view returns (address) {
        return _constants().arbTokenAddress;
    }

    function setArbTokenAddress(address arbTokenAddress_) public ownerOnly {
        _constants().arbTokenAddress = arbTokenAddress_;
    }

    function getBattlePassUsdPrice() public view returns (uint256) {
        return _constants().battlePassUsdPrice;
    }

    function setBattlePassUsdPrice(
        uint256 price
    ) public ownerOnly {
        _constants().battlePassUsdPrice = price;
    }

    function getCurrentBattlePassSeason() public view returns (uint8) {
        return _token().currentBattlePassSeason;
    }

    function setCurrentBattlePassSeason(
        uint8 season
    ) public ownerOnly {
        _token().currentBattlePassSeason = season;
    }

    function getBattlePassSeasonIsOpen() public view returns (bool) {
        return _token().battlePassIsOpen;
    }

    function setBattlePassSeasonIsOpen(
        bool isOpen
    ) public ownerOnly {
        _token().battlePassIsOpen = isOpen;
    }

    function getBattlePassSeasonClaimed(address account) public view returns (bool) {
        uint8 currentBattlePassSeason = getCurrentBattlePassSeason();
        if (currentBattlePassSeason == 0) return false;
        if (getBattlePassSeasonIsOpen() == false) return false;
        return _token().battlePassSeasonClaimed[account] == currentBattlePassSeason;
    }
}


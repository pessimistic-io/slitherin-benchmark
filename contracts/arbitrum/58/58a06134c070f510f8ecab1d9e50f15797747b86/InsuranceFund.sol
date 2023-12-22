// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "./IERC20.sol";
import { Decimal } from "./Decimal.sol";
import { IInsuranceFund } from "./IInsuranceFund.sol";
import { DecimalERC20 } from "./DecimalERC20.sol";
import { IAmm } from "./IAmm.sol";

contract InsuranceFund is
    IInsuranceFund,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    DecimalERC20
{
    using Decimal for Decimal.decimal;

    //
    // EVENTS
    //

    event Withdrawn(address withdrawer, uint256 amount);
    event TokenAdded(address tokenAddress);
    event TokenRemoved(address tokenAddress);
    event AmmAdded(address amm);
    event AmmRemoved(address amm);

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    mapping(address => bool) public ammMap;
    mapping(address => bool) private quoteTokenMap;
    IAmm[] private amms;
    IERC20[] public quoteTokens;

    // contract dependencies
    address private beneficiary;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //

    function initialize() external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /**
     * @dev only owner can call
     * @param _amm IAmm address
     */
    function addAmm(IAmm _amm) external onlyOwner {
        require(!isExistedAmm(_amm), "amm already added");
        ammMap[address(_amm)] = true;
        amms.push(_amm);
        emit AmmAdded(address(_amm));

        // add token if it's new one
        IERC20 token = IAmm(_amm).quoteAsset();
        if (!isQuoteTokenExisted(token)) {
            quoteTokens.push(token);
            quoteTokenMap[address(token)] = true;
            emit TokenAdded(address(token));
        }
    }

    /**
     * @dev only owner can call. no need to call
     * @param _amm IAmm address
     */
    function removeAmm(IAmm _amm) external onlyOwner {
        require(isExistedAmm(_amm), "amm not existed");
        ammMap[address(_amm)] = false;
        uint256 ammLength = amms.length;
        for (uint256 i = 0; i < ammLength; i++) {
            if (amms[i] == _amm) {
                amms[i] = amms[ammLength - 1];
                amms.pop();
                emit AmmRemoved(address(_amm));
                break;
            }
        }
    }

    function removeToken(IERC20 _token) external onlyOwner {
        require(isQuoteTokenExisted(_token), "token not existed");

        quoteTokenMap[address(_token)] = false;
        uint256 quoteTokensLength = getQuoteTokenLength();
        for (uint256 i = 0; i < quoteTokensLength; i++) {
            if (quoteTokens[i] == _token) {
                if (i < quoteTokensLength - 1) {
                    quoteTokens[i] = quoteTokens[quoteTokensLength - 1];
                }
                quoteTokens.pop();
                break;
            }
        }

        if (balanceOf(_token).toUint() > 0) {
            _token.transfer(owner(), balanceOf(_token).toUint());
        }

        emit TokenRemoved(address(_token));
    }

    /**
     * @notice withdraw token to caller
     * @param _amount the amount of quoteToken caller want to withdraw
     */
    function withdraw(IERC20 _quoteToken, Decimal.decimal calldata _amount) external {
        IERC20 quoteToken = IERC20(_quoteToken);

        require(beneficiary == _msgSender(), "caller is not beneficiary");
        require(isQuoteTokenExisted(quoteToken), "Asset is not supported");

        Decimal.decimal memory quoteBalance = balanceOf(quoteToken);

        require(quoteBalance.toUint() >= _amount.toUint(), "Fund not enough");

        _transfer(quoteToken, _msgSender(), _amount);
        emit Withdrawn(_msgSender(), _amount.toUint());
    }

    //
    // SETTER
    //

    function setBeneficiary(address _beneficiary) external onlyOwner {
        beneficiary = _beneficiary;
    }

    function getQuoteTokenLength() public view returns (uint256) {
        return quoteTokens.length;
    }

    //
    // INTERNAL FUNCTIONS
    //

    //
    // VIEW
    //
    function isExistedAmm(IAmm _amm) public view returns (bool) {
        return ammMap[address(_amm)];
    }

    function getAllAmms() external view returns (IAmm[] memory) {
        return amms;
    }

    function isQuoteTokenExisted(IERC20 _token) internal view returns (bool) {
        return quoteTokenMap[address(_token)];
    }

    function balanceOf(IERC20 _quoteToken) internal view returns (Decimal.decimal memory) {
        return _balanceOf(_quoteToken, address(this));
    }
}


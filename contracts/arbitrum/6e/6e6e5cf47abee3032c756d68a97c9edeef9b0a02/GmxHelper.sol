// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IGmxHelper.sol";
import {IGmxVault} from "./IGmxVault.sol";
import {IGmxReader} from "./IGmxReader.sol";

contract GmxHelper is IGmxHelper {
    address private owner;

    IGmxVault public gmxVault;

    IGmxReader public gmxReader;

    address private GMX_VAULT_ADDRESS;

    address private WETH_TOKEN;

    event NewOwnerSet(address _newOwner, address _olderOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "gmxHelper: Forbidden");
        _;
    }

    constructor(address _vault, address _weth, address _reader) {
        gmxVault = IGmxVault(_vault);

        gmxReader = IGmxReader(_reader);

        WETH_TOKEN = _weth;

        owner = msg.sender;
    }

    function setOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;
        emit NewOwnerSet(_newOwner, msg.sender);
    }

    function setAddresses(address _vault, address _reader) external onlyOwner {
        gmxVault = IGmxVault(_vault);
        gmxReader = IGmxReader(_reader);
    }

    /**
     * @notice Calculate leverage from collateral and size.
     * @param _collateralToken Address of the collateral token or input
     *                         token.
     * @param _indexToken      Address of the index token longing on.
     * @param _collateralDelta  Amount of collateral in collateral token decimals.
     * @param _sizeDelta        Size of the position usd in 1e30 decimals.
     * @return _positionLeverage
     */
    function getPositionLeverage(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) public view returns (uint256 _positionLeverage) {
        _positionLeverage = ((_sizeDelta * 1e30) /
            calculateCollateral(
                _collateralToken,
                _indexToken,
                _collateralDelta,
                _sizeDelta
            ));
    }

    /**
     * @notice Calculate collateral amount in 1e30 usd decimal
     *         given the input amount of token in its own decimals.
     *         considers position fee and swap fees before calculating
     *         output amount.
     * @param _collateralToken  Address of the input token or collateral token.
     * @param _indexToken       Address of the index token to long for.
     * @param _collateralAmount Amount of collateral in collateral token decimals.
     * @param _sizeDelta            Size of the position usd in 1e30 decimals.
     * @return collateral
     */
    function calculateCollateral(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralAmount,
        uint256 _sizeDelta
    ) public view returns (uint256 collateral) {
        uint256 marginFees = getPositionFee(_sizeDelta);
        if (_collateralToken != _indexToken) {
            (collateral, ) = gmxReader.getAmountOut(
                gmxVault,
                _collateralToken,
                _indexToken,
                _collateralAmount
            );
            collateral = gmxVault.tokenToUsdMin(_indexToken, collateral);
        } else {
            collateral = gmxVault.tokenToUsdMin(
                _collateralToken,
                _collateralAmount
            );
        }
        require(marginFees < collateral, "Utils: Fees exceed collateral");
        collateral -= marginFees;
    }

    /**
     * @notice Calculate collateral amount in 1e30 usd decimal
     *         given the input amount of token in its own decimals.
     *         considers position fee and swap fees before calculating
     *         output amount.
     * @param _collateralToken  Address of the input token or collateral token.
     * @param _indexToken       Address of the index token to long for.
     * @param _collateralDelta Amount of collateral in collateral token decimals.
     * @return collateral
     */
    function calculateCollateralDelta(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta
    ) public view returns (uint256 collateral) {
        if (_collateralToken != _indexToken) {
            uint256 priceIn = getMinPrice(_collateralToken);
            uint256 priceOut = getMaxPrice(_indexToken);
            collateral = adjustForDecimals(
                (_collateralDelta * priceIn) / priceOut,
                _collateralToken,
                _indexToken
            );
        } else collateral = _collateralDelta;
    }

    /**
     * @notice Check if collateral amount is sufficient
     *         to open a long position.
     * @param _collateralSize  Amount of collateral in its own decimals
     * @param _size            Total Size of the position in usd 1e30
     *                         decimals.
     * @param _collateralToken Address of the collateral token or input
     *                         token.
     * @param _indexToken      Address of the index token longing on
     */
    function validateLongIncreaseExecution(
        uint256 _collateralSize,
        uint256 _size,
        address _collateralToken,
        address _indexToken
    ) public view returns (bool) {
        if (_collateralToken != _indexToken) {
            (_collateralSize, ) = gmxReader.getAmountOut(
                gmxVault,
                _collateralToken,
                _indexToken,
                _collateralSize
            );
        }

        return
            gmxVault.tokenToUsdMin(_indexToken, _collateralSize) >
            getPositionFee(_size) + gmxVault.liquidationFeeUsd();
    }

    /**
     * @notice Check if collateral amount is sufficient
     *         to open a long position.
     * @param _collateralSize  Amount of collateral in its own decimals
     * @param _size            Total Size of the position in usd 1e30
     *                         decimals.
     * @param _collateralToken Address of the collateral token or input
     *                         token.
     */
    function validateShortIncreaseExecution(
        uint256 _collateralSize,
        uint256 _size,
        address _collateralToken
    ) public view returns (bool) {
        return
            gmxVault.tokenToUsdMin(_collateralToken, _collateralSize) >
            getPositionFee(_size) + gmxVault.liquidationFeeUsd();
    }

    /**
     * @notice Get fee charged on opening and closing a position on gmx.
     * @param  _size  Total size of the position in 30 decimal usd precision value.
     * @return feeUsd Fee in 30 decimal usd precision value.
     */
    function getPositionFee(
        uint256 _size
    ) public view returns (uint256 feeUsd) {
        address gov = gmxVault.gov();
        uint256 marginFeeBps = IGmxVault(gov).marginFeeBasisPoints();
        feeUsd = _size - ((_size * (10000 - marginFeeBps)) / 10000);
    }

    function getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    )
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool,
            uint256
        )
    {
        return
            gmxVault.getPosition(
                _account,
                _collateralToken,
                _indexToken,
                _isLong
            );
    }

    function tokenDecimals(address _token) public view returns (uint256) {
        return gmxVault.tokenDecimals(_token);
    }

    function adjustForDecimals(
        uint256 _amount,
        address _tokenDiv,
        address _tokenMul
    ) public view returns (uint256) {
        return gmxVault.adjustForDecimals(_amount, _tokenDiv, _tokenMul);
    }

    function getMinPrice(address _token) public view returns (uint256) {
        return gmxVault.getMinPrice(_token);
    }

    function getMaxPrice(address _token) public view returns (uint256) {
        return gmxVault.getMaxPrice(_token);
    }

    function tokenToUsdMin(
        address _token,
        uint256 _tokenAmount
    ) public view returns (uint256) {
        return gmxVault.tokenToUsdMin(_token, _tokenAmount);
    }

    function getPositionKey(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view override returns (bytes32) {
        return
            gmxVault.getPositionKey(
                _account,
                _collateralToken,
                _indexToken,
                _isLong
            );
    }

    function usdToTokenMin(
        address _token,
        uint256 _tokenAmount
    ) external view returns (uint256) {
        return gmxVault.tokenToUsdMin(_token, _tokenAmount);
    }

    function getWethToken() external view override returns (address) {
        return WETH_TOKEN;
    }

    function getGmxDecimals() external pure returns (uint256) {
        // return IGmxVault(getGmxVault()).PRICE_PRECISION();
        return 1e30;
    }

    // function validateDecreaseCollateralDelta(
    //     address _externalPosition,
    //     address _indexToken,
    //     address _collateralToken,
    //     uint256 _collateralDelta
    // ) external view returns (bool valid) {
    //     bool isLong = _collateralToken== _indexToken;
    //     (uint256 size, uint256 collateral, , , , , , ) = vault.getPosition(
    //         _externalPosition,
    //         _collateralToken,
    //         _indexToken,
    //         isLong
    //     );

    //     (bool hasProfit, uint256 delta) = vault.getPositionDelta(
    //         _externalPosition,
    //         _collateralToken,
    //         _indexToken,
    //         isLong
    //     );

    //     uint256 feeUsd = getFundingFee(
    //         _indexToken,
    //         ,
    //         address(0)
    //     ) + getPositionFee(size);

    //     collateral -= _collateralDelta;
    //     delta += feeUsd;

    //     uint256 newLeverage = (size * 10000) / collateral;

    //     valid = true;

    //     if (vault.maxLeverage() < newLeverage) {
    //         valid = false;
    //     }

    //     if (!hasProfit && delta > collateral) {
    //         valid = false;
    //     }
    // }
}


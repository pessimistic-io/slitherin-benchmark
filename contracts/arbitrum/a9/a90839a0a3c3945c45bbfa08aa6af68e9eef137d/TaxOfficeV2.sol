// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Operator.sol";
import "./ITaxable.sol";
import "./IUniswapV2Router.sol";
import "./IERC20.sol";

contract TaxOfficeV2 is Operator {
    using SafeMath for uint256;

    address public atomb = address(0xb48A5cBb404b0C0903e00E638a5F545c96a12202); 
    address public weth = address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    address public uniRouter = address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    mapping(address => bool) public taxExclusionEnabled;

    function setTaxTiersTwap(uint8 _index, uint256 _value)
        public
        onlyOperator
        returns (bool)
    {
        return ITaxable(atomb).setTaxTiersTwap(_index, _value);
    }

    function setTaxTiersRate(uint8 _index, uint256 _value)
        public
        onlyOperator
        returns (bool)
    {
        return ITaxable(atomb).setTaxTiersRate(_index, _value);
    }

    function enableAutoCalculateTax() public onlyOperator {
        ITaxable(atomb).enableAutoCalculateTax();
    }

    function disableAutoCalculateTax() public onlyOperator {
        ITaxable(atomb).disableAutoCalculateTax();
    }

    function setTaxRate(uint256 _taxRate) public onlyOperator {
        ITaxable(atomb).setTaxRate(_taxRate);
    }

    function setBurnThreshold(uint256 _burnThreshold) public onlyOperator {
        ITaxable(atomb).setBurnThreshold(_burnThreshold);
    }

    function setTaxCollectorAddress(address _taxCollectorAddress)
        public
        onlyOperator
    {
        ITaxable(atomb).setTaxCollectorAddress(_taxCollectorAddress);
    }

    function excludeAddressFromTax(address _address)
        external
        onlyOperator
        returns (bool)
    {
        return _excludeAddressFromTax(_address);
    }

    function _excludeAddressFromTax(address _address) private returns (bool) {
        if (!ITaxable(atomb).isAddressExcluded(_address)) {
            return ITaxable(atomb).excludeAddress(_address);
        }
    }

    function includeAddressInTax(address _address)
        external
        onlyOperator
        returns (bool)
    {
        return _includeAddressInTax(_address);
    }

    function _includeAddressInTax(address _address) private returns (bool) {
        if (ITaxable(atomb).isAddressExcluded(_address)) {
            return ITaxable(atomb).includeAddress(_address);
        }
    }

    function taxRate() external returns (uint256) {
        return ITaxable(atomb).taxRate();
    }

    function addLiquidityTaxFree(
        address token,
        uint256 amtATomb,
        uint256 amtToken,
        uint256 amtATombMin,
        uint256 amtTokenMin
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtATomb != 0 && amtToken != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(atomb).transferFrom(msg.sender, address(this), amtATomb);
        IERC20(token).transferFrom(msg.sender, address(this), amtToken);
        _approveTokenIfNeeded(atomb, uniRouter);
        _approveTokenIfNeeded(token, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtATomb;
        uint256 resultAmtToken;
        uint256 liquidity;
        (resultAmtATomb, resultAmtToken, liquidity) = IUniswapV2Router(
            uniRouter
        ).addLiquidity(
                atomb,
                token,
                amtATomb,
                amtToken,
                amtATombMin,
                amtTokenMin,
                msg.sender,
                block.timestamp
            );

        if (amtATomb.sub(resultAmtATomb) > 0) {
            IERC20(atomb).transfer(msg.sender, amtATomb.sub(resultAmtATomb));
        }
        if (amtToken.sub(resultAmtToken) > 0) {
            IERC20(token).transfer(msg.sender, amtToken.sub(resultAmtToken));
        }
        return (resultAmtATomb, resultAmtToken, liquidity);
    }

    function addLiquidityETHTaxFree(
        uint256 amtATomb,
        uint256 amtATombMin,
        uint256 amtEthMin
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtATomb != 0 && msg.value != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(atomb).transferFrom(msg.sender, address(this), amtATomb);
        _approveTokenIfNeeded(atomb, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtATomb;
        uint256 resultAmtEth;
        uint256 liquidity;
        (resultAmtATomb, resultAmtEth, liquidity) = IUniswapV2Router(uniRouter)
            .addLiquidityETH{value: msg.value}(
            atomb,
            amtATomb,
            amtATombMin,
            amtEthMin,
            msg.sender,
            block.timestamp
        );

        if (amtATomb.sub(resultAmtATomb) > 0) {
            IERC20(atomb).transfer(msg.sender, amtATomb.sub(resultAmtATomb));
        }
        return (resultAmtATomb, resultAmtEth, liquidity);
    }

    function setTaxableATombOracle(address _atombOracle) external onlyOperator {
        ITaxable(atomb).setATombOracle(_atombOracle);
    }

    function transferTaxOffice(address _newTaxOffice) external onlyOperator {
        ITaxable(atomb).setTaxOffice(_newTaxOffice);
    }

    function taxFreeTransferFrom(
        address _sender,
        address _recipient,
        uint256 _amt
    ) external {
        require(
            taxExclusionEnabled[msg.sender],
            "Address not approved for tax free transfers"
        );
        _excludeAddressFromTax(_sender);
        IERC20(atomb).transferFrom(_sender, _recipient, _amt);
        _includeAddressInTax(_sender);
    }

    function setTaxExclusionForAddress(address _address, bool _excluded)
        external
        onlyOperator
    {
        taxExclusionEnabled[_address] = _excluded;
    }

    function _approveTokenIfNeeded(address _token, address _router) private {
        if (IERC20(_token).allowance(address(this), _router) == 0) {
            IERC20(_token).approve(_router, type(uint256).max);
        }
    }
}

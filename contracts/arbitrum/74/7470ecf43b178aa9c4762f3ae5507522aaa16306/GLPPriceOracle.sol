// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IPriceOracle } from "./IPriceOracle.sol";
import { Ownable } from "./Ownable.sol";
import { Address } from "./Address.sol";
import { IGLPManager } from "./IGLPManager.sol";
import { ParseBytes } from "./ParseBytes.sol";

contract GLPPriceOracle is IPriceOracle, Ownable {
    using Address for address;
    using ParseBytes for bytes;

    string public description;
    uint8 public decimals;
    address public asset;

    // GLP has default precision as 30
    uint8 public constant MAX_DECIMALS = 30;

    // GLP Manager address
    IGLPManager public glpManager;

    constructor(string memory _description, address _underlying, uint8 _decimals, address _glpManager) {
        if (_decimals > MAX_DECIMALS) revert InvalidDecimals();
        if (!_glpManager.isContract()) revert notContract();

        description = _description;
        decimals = _decimals;
        asset = _underlying;
        glpManager = IGLPManager(_glpManager);
    }

    function getLatestPrice(
        bytes calldata _maximise
    )
        external
        view
        override
        returns (uint256 _currentPrice, uint256 _lastPrice, uint256 _lastUpdateTimestamp, uint8 _decimals)
    {
        bool isMax = _maximise.parse32BytesToBool();
        uint256 price = glpManager.getPrice(isMax);
        return (price, price, block.timestamp, decimals);
    }

    function setGlpManager(address _glpManager) external onlyOwner {
        if (!_glpManager.isContract()) revert notContract();
        glpManager = IGLPManager(_glpManager);
    }
}


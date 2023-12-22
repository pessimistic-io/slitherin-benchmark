// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {IReader} from "./IReader.sol";
import {IGmxVault} from "./IGmxVault.sol";
import {IBaseToken} from "./IBaseToken.sol";
import {IGmxVaultPriceFeed} from "./IGmxVaultPriceFeed.sol";

/// @title Reader
/// @author 7811, abhi3700
/// @notice Contract with view functions to get more info on the Stfs
/// @dev this contract is used by the StfxVault and the Stfx contract
contract Reader is IReader {
    // struct which contains all the necessary contract addresses of GMX
    // check `IReaderStorage.Gmx`
    Gmx public dex;
    // owner/deployer of this contract
    address public owner;

    /// @notice constructor
    /// @param _dex `Gmx` struct which contains the necessary contract addresses of GMX
    constructor(Gmx memory _dex) {
        dex = _dex;
        owner = msg.sender;
    }

    /// @notice get gmx's contract addresses
    /// @dev view function
    /// @return dexAddress - an array of gmx's contract addresses
    ///         dexAddress[0] = Gmx.Vault
    ///         dexAddress[1] = Gmx.Router
    ///         dexAddress[2] = Gmx.PositionRouter
    ///         dexAddress[3] = Gmx.OrderBook
    ///         dexAddress[4] = Gmx.Reader
    function getDex() external view override returns (address[] memory dexAddress) {
        dexAddress = new address[](5);
        dexAddress[0] = dex.vault;
        dexAddress[1] = dex.router;
        dexAddress[2] = dex.positionRouter;
        dexAddress[3] = dex.orderBook;
        dexAddress[4] = dex.reader;
    }

    /// @notice checks if an ERC20 token can be used to open a trade on GMX
    /// @dev view function
    /// @param _baseToken address of the ERC20 token which is used for the trade
    /// @return true if the `_baseToken` is eligible
    function getBaseTokenEligible(address _baseToken) external view override returns (bool) {
        return IGmxVault(dex.vault).shortableTokens(_baseToken);
    }

    /// @notice gets the current price of the `_baseToken` from GMX
    /// @dev view function, the price returned from gmx is in 1e30 units
    /// @param _baseToken address of the ERC20 token which is used for the trade
    /// @return price - the current price of the `_baseToken`
    /// @return denominator - the denominator which is used in `checkPrices()`
    function getPrice(address _baseToken) public view override returns (uint256, uint256) {
        address vaultPriceFeed = IGmxVault(dex.vault).priceFeed();
        return (IGmxVaultPriceFeed(vaultPriceFeed).getPrice(_baseToken, true, true, false), 1e24);
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param _entry the entry price which has been given as input from the manager when creating an stf
    /// @param _target the target price which has been given as input from the manager when creating an stf
    /// @param _baseToken the baseToken which the manager wants to open a trade in
    /// @param _tradeDirection the direction of the trade which the manager wants to open, true = long, false = short
    /// @return true if the entry and the target price are under the lower and the upper limit
    function checkPrices(uint256 _entry, uint256 _target, address _baseToken, bool _tradeDirection)
        external
        view
        returns (bool)
    {
        (uint256 price, uint256 denominator) = getPrice(_baseToken);
        uint256 lower = price / (denominator * 10);
        uint256 upper = (price * 10) / denominator;

        if (_tradeDirection) {
            require(lower <= _entry, "entry should be more than lower");
            require(_entry < _target, "entry should be less than target");
            require(_target <= upper, "target should be less than upper");
        } else {
            require(lower <= _target, "target should be more than lower");
            require(_target < _entry, "target should be less than entry");
            require(_entry <= upper, "entry should be less than upper");
        }

        return true;
    }

    /// @notice function to set/update the necessary contract addresses of gmx
    /// @dev can only be called by the owner
    /// @param _dex `Gmx` struct which contains the necessary contract addresses of GMX
    function setDex(Gmx calldata _dex) external {
        require(msg.sender == owner, "Not owner");
        dex = _dex;
    }
    
    /// @notice function to set the owner of the `Reader` contract
    /// @dev can only be called by the owner
    /// @param _owner new owner address
    function setOwner(address _owner) external {
        require(msg.sender == owner, "Not owner");
        require(_owner != address(0), "Not zero address");
        owner = _owner;
    }
}


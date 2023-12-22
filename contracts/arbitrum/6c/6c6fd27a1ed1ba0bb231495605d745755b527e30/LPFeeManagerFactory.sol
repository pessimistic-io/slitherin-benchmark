// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

/*
  ______                     ______                                 
 /      \                   /      \                                
|  ▓▓▓▓▓▓\ ______   ______ |  ▓▓▓▓▓▓\__   __   __  ______   ______  
| ▓▓__| ▓▓/      \ /      \| ▓▓___\▓▓  \ |  \ |  \|      \ /      \ 
| ▓▓    ▓▓  ▓▓▓▓▓▓\  ▓▓▓▓▓▓\\▓▓    \| ▓▓ | ▓▓ | ▓▓ \▓▓▓▓▓▓\  ▓▓▓▓▓▓\
| ▓▓▓▓▓▓▓▓ ▓▓  | ▓▓ ▓▓    ▓▓_\▓▓▓▓▓▓\ ▓▓ | ▓▓ | ▓▓/      ▓▓ ▓▓  | ▓▓
| ▓▓  | ▓▓ ▓▓__/ ▓▓ ▓▓▓▓▓▓▓▓  \__| ▓▓ ▓▓_/ ▓▓_/ ▓▓  ▓▓▓▓▓▓▓ ▓▓__/ ▓▓
| ▓▓  | ▓▓ ▓▓    ▓▓\▓▓     \\▓▓    ▓▓\▓▓   ▓▓   ▓▓\▓▓    ▓▓ ▓▓    ▓▓
 \▓▓   \▓▓ ▓▓▓▓▓▓▓  \▓▓▓▓▓▓▓ \▓▓▓▓▓▓  \▓▓▓▓▓\▓▓▓▓  \▓▓▓▓▓▓▓ ▓▓▓▓▓▓▓ 
         | ▓▓                                             | ▓▓      
         | ▓▓                                             | ▓▓      
          \▓▓                                              \▓▓         

 * App:             https://apeswap.finance
 * Medium:          https://ape-swap.medium.com
 * Twitter:         https://twitter.com/ape_swap
 * Discord:         https://discord.com/invite/apeswap
 * Telegram:        https://t.me/ape_swap
 * Announcements:   https://t.me/ape_swap_news
 * GitHub:          https://github.com/ApeSwapFinance
 */

import "./FactoryUpgradeable.sol";
import "./IApeRouter02.sol";

interface ILPFeeManagerV2 {
    function initialize(address _router) external;

    function transferOwnership(address newOwner) external;
}

/// @title LPFeeManagerFactory
/// @author ApeSwap.finance
/// @notice Manage and deploy fee manager contracts
contract LPFeeManagerFactory is FactoryUpgradeable {
    address public router;
    address public defaultLpFeeManagerOwner;

    event UpdateRouter(address indexed oldRouter, address indexed newRouter);
    event UpdateDefaultLpFeeManagerOwner(
        address indexed oldDefaultLpFeeManagerOwner,
        address indexed newDefaultLpFeeManagerOwner
    );

    constructor(
        address _implementation,
        address _proxyAdmin,
        address _defaultLpFeeManagerOwner,
        address _router
    ) FactoryUpgradeable(_implementation, _proxyAdmin) {
        _updateRouterAddress(_router);
        _updateDefaultLpFeeManagerOwner(_defaultLpFeeManagerOwner);
    }

    /**
     * @dev Deploy new LpFeeManager contract
     * @notice This function is open to the public as the owner of the deployed LpFeeManager is set by onlyOwner
     */
    function deployNewLPFeeManagerContract() external {
        ILPFeeManagerV2 newLPFeeManager = ILPFeeManagerV2(_deployNewContract());
        newLPFeeManager.initialize(router);
        newLPFeeManager.transferOwnership(defaultLpFeeManagerOwner);
    }

    /**
     * @dev Deploy new LpFeeManager contract with a custom router contract
     * @notice This function is open to the public as the owner of the deployed LpFeeManager is set by onlyOwner
     * @param _router The router address to be used to initialize the new LpFeeManager contract
     */
    function deployNewLPFeeManagerContract_CustomRouter(
        address _router
    ) external {
        ILPFeeManagerV2 newLPFeeManager = ILPFeeManagerV2(_deployNewContract());
        newLPFeeManager.initialize(_router);
        newLPFeeManager.transferOwnership(defaultLpFeeManagerOwner);
    }

    /**
     * @dev Update the router address which is used to initialize new LpFeeManager contracts
     */
    function updateRouterAddress(address _router) external onlyOwner {
        _updateRouterAddress(_router);
    }

    /**
     * @dev Update the address which is set as the owner of newly deployed LpFeeManagerContracts
     */
    function updateDefaultLpFeeManagerOwner(
        address _defaultLpFeeManagerOwner
    ) external onlyOwner {
        _updateDefaultLpFeeManagerOwner(_defaultLpFeeManagerOwner);
    }

    function _updateRouterAddress(address _router) internal {
        try IApeRouter02(_router).factory() {
            emit UpdateRouter(router, _router);
            router = _router;
        } catch (bytes memory) {
            revert("LPFeeManagerFactory:: Check router address");
        }
    }

    function _updateDefaultLpFeeManagerOwner(
        address _defaultLpFeeManagerOwner
    ) internal {
        require(
            _defaultLpFeeManagerOwner != address(0),
            "LPFeeManagerFactory:: Cannot be address(0)"
        );
        emit UpdateDefaultLpFeeManagerOwner(
            defaultLpFeeManagerOwner,
            _defaultLpFeeManagerOwner
        );
        defaultLpFeeManagerOwner = _defaultLpFeeManagerOwner;
    }
}


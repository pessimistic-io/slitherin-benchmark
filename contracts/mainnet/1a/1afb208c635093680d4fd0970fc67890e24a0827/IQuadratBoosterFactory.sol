// SPDX-License-Identifier: MIT

/***
 *      ______             _______   __
 *     /      \           |       \ |  \
 *    |  $$$$$$\ __    __ | $$$$$$$\| $$  ______    _______  ______ ____    ______
 *    | $$$\| $$|  \  /  \| $$__/ $$| $$ |      \  /       \|      \    \  |      \
 *    | $$$$\ $$ \$$\/  $$| $$    $$| $$  \$$$$$$\|  $$$$$$$| $$$$$$\$$$$\  \$$$$$$\
 *    | $$\$$\$$  >$$  $$ | $$$$$$$ | $$ /      $$ \$$    \ | $$ | $$ | $$ /      $$
 *    | $$_\$$$$ /  $$$$\ | $$      | $$|  $$$$$$$ _\$$$$$$\| $$ | $$ | $$|  $$$$$$$
 *     \$$  \$$$|  $$ \$$\| $$      | $$ \$$    $$|       $$| $$ | $$ | $$ \$$    $$
 *      \$$$$$$  \$$   \$$ \$$       \$$  \$$$$$$$ \$$$$$$$  \$$  \$$  \$$  \$$$$$$$
 *
 *
 *
 */

pragma solidity >=0.8.0;

import {IBeacon} from "./IBeacon.sol";

interface IQuadratBoosterFactory {
    function deployBooster(bytes calldata payaload_, bool isBeacon_)
        external
        payable
        returns (address);

    function upgradeBoosters(address[] calldata boosters_) external;

    function upgradeBoostersAndCall(
        address[] memory boosters_,
        bytes[] calldata datas_
    ) external;

    function makeBoostersImmutable(address[] calldata boosters_) external;

    function setFee(uint256 fee_) external;

    function withdrawFee(address to) external;

    function transferBoosterOwnership(address newOwner) external;

    function addUserBooster(address user) external;

    function removeUserBooster(address user) external;

    function transferUserBooster(address oldUser, address newUser) external;

    // #region view functions

    function fee() external view returns (uint256);

    function beacon() external view returns (IBeacon);

    function boosters(uint256 startIndex_, uint256 endIndex_)
        external
        view
        returns (address[] memory);

    function numBoosters() external view returns (uint256);

    function ownerBoosters(
        address owner,
        uint256 startIndex_,
        uint256 endIndex_
    ) external view returns (address[] memory);

    function numOwnerBoosters(address owner) external view returns (uint256);

    function tokenBoosters(
        address token,
        uint256 startIndex_,
        uint256 endIndex_
    ) external view returns (address[] memory);

    function numTokenBoosters(address token) external view returns (uint256);

    function userBoosters(
        address user,
        uint256 startIndex_,
        uint256 endIndex_
    ) external view returns (address[] memory);

    function numUserBoosters(address user) external view returns (uint256);

    function isBooster(address) external view returns (bool);

    function getProxyAdmin(address proxy) external view returns (address);

    function getProxyImplementation(address proxy)
        external
        view
        returns (address);

    // #endregion view functions

    event FeeSet(uint256);
    event FeeWithdrawn(address, address, uint256);
    event BoostersUpgraded(address[] boosters_, address indexed implementation);
    event BoostersUpgradedAndCalled(
        address[] boosters_,
        bytes[] data_,
        address indexed implementation
    );
    event BoostersImmuted(address[] boosters_);
    event BoosterCreated(
        address indexed owner,
        address indexed booster,
        uint256 fee
    );
}


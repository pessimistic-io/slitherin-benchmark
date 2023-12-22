// SPDX-License-Identifier: BUSL-1.1

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

pragma solidity 0.8.13;

import {IQuadratBoosterFactory} from "./IQuadratBoosterFactory.sol";
import {     ITransparentUpgradeableProxy } from "./ITransparentUpgradeableProxy.sol";
import {IBeacon} from "./IBeacon.sol";
import {     OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import {     EnumerableSet } from "./EnumerableSet.sol";

/// @title Quadrat Booster Factory Storage Smart Contract
// solhint-disable-next-line max-states-count
abstract contract QuadratBoosterFactoryStorage is
    IQuadratBoosterFactory,
    OwnableUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    IBeacon public immutable override beacon;
    EnumerableSet.AddressSet internal _boosters;
    uint256 public override fee;

    mapping(address => EnumerableSet.AddressSet) internal _ownerBoosters;
    mapping(address => address[]) internal _tokenBoosters;
    mapping(address => EnumerableSet.AddressSet) internal _userBoosters;

    modifier initialized() {
        require(owner() != address(0), "NI");
        _;
    }

    // #region constructor.

    constructor(IBeacon beacon_) {
        beacon = beacon_;
        _disableInitializers();
    }

    // #endregion constructor.

    function initialize(address _owner_) external initializer {
        require(_owner_ != address(0), "ZA");
        _transferOwnership(_owner_);
    }

    // #region admin set functions

    /// @notice sets deployment fee
    /// @param fee_ Deplyment fee in native token
    /// @dev only callable by owner
    function setFee(uint256 fee_) external override onlyOwner {
        require(fee != fee_, "RA");
        fee = fee_;
        emit FeeSet(fee_);
    }

    /// @notice upgrade boosters instance using transparent proxy
    /// with the current implementation
    /// @param boosters_ the list of boosters.
    /// @dev only callable by owner
    function upgradeBoosters(address[] calldata boosters_) external onlyOwner {
        address implementation = beacon.implementation();
        require(implementation != address(0), "ZA");
        require(boosters_.length > 0, "AL");
        for (uint256 i = 0; i < boosters_.length; i++) {
            ITransparentUpgradeableProxy(boosters_[i]).upgradeTo(
                implementation
            );
        }
        emit BoostersUpgraded(boosters_, implementation);
    }

    /// @notice upgrade boosters instance using transparent proxy
    /// with the current implementation and call the instance
    /// @param boosters_ the list of boosters.
    /// @param datas_ payloads of instances call.
    /// @dev only callable by owner
    function upgradeBoostersAndCall(
        address[] calldata boosters_,
        bytes[] calldata datas_
    ) external onlyOwner {
        address implementation = beacon.implementation();
        require(implementation != address(0), "ZA");
        require(
            boosters_.length > 0 && boosters_.length == datas_.length,
            "AL"
        );
        for (uint256 i = 0; i < boosters_.length; i++) {
            ITransparentUpgradeableProxy(boosters_[i]).upgradeToAndCall(
                implementation,
                datas_[i]
            );
        }
        emit BoostersUpgradedAndCalled(boosters_, datas_, implementation);
    }

    /// @notice make the booster immutable
    /// @param boosters_ the list of boosters.
    /// @dev only callable by owner
    function makeBoostersImmutable(address[] calldata boosters_)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < boosters_.length; i++) {
            ITransparentUpgradeableProxy(boosters_[i]).changeAdmin(address(1));
        }
        emit BoostersImmuted(boosters_);
    }

    // #endregion admin set functions

    // #region admin view call.

    /// @notice get booster instance admin
    /// @param proxy instance of Quadrat Booster.
    /// @return admin address of Quadrat Booster instance admin.
    function getProxyAdmin(address proxy) external view returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("admin()")) == 0xf851a440
        (bool success, bytes memory returndata) = proxy.staticcall(
            hex"f851a440"
        );
        require(success, "PA");
        return abi.decode(returndata, (address));
    }

    /// @notice get booster implementation
    /// @param proxy instance of Quadrat Booster.
    /// @return implementation address of Quadrat Booster implementation.
    function getProxyImplementation(address proxy)
        external
        view
        returns (address)
    {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("implementation()")) == 0x5c60da1b
        (bool success, bytes memory returndata) = proxy.staticcall(
            hex"5c60da1b"
        );
        require(success, "PI");
        return abi.decode(returndata, (address));
    }

    // #endregion admin view call.
}


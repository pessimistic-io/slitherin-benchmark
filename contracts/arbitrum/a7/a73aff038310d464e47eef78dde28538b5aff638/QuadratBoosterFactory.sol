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

import {Address} from "./Address.sol";
import {     TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";
import {     BeaconProxy,     IBeacon } from "./BeaconProxy.sol";
import {     EnumerableSet } from "./EnumerableSet.sol";

import {IQuadratBooster} from "./IQuadratBooster.sol";
import {     OwnableUpgradeable,     QuadratBoosterFactoryStorage } from "./QuadratBoosterFactoryStorage.sol";

import {BasePayload} from "./SQuadratBooster.sol";

/// @title QuadratBoosterFactoryStorage factory for creating booster instances.
contract QuadratBoosterFactory is QuadratBoosterFactoryStorage {
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;

    // solhint-disable-next-line max-line-length
    constructor(IBeacon beacon_) QuadratBoosterFactoryStorage(beacon_) {} // solhint-disable-line no-empty-blocks

    /// @notice Deploys an instance of Booster using BeaconProxy or TransparentProxy.
    /// @param params_ contains all data needed to create an instance of QuadratBooster.
    /// @param isBeacon_ boolean, if true the instance will be BeaconProxy or TransparentProxy.
    /// @return booster the address of the QuadratBooster instance created.
    function deployBooster(bytes calldata params_, bool isBeacon_)
        external
        payable
        override
        initialized
        returns (address booster)
    {
        uint256 _value = msg.value;
        uint256 _fee = fee;
        require(_value >= _fee, "FA");
        booster = _preDeploy(params_, isBeacon_);
        BasePayload memory payload = IQuadratBooster(beacon.implementation())
            .transformBytesToBasePayload(params_);
        _boosters.add(booster);
        _ownerBoosters[payload.owner].add(booster);
        _tokenBoosters[payload.depositToken].push(booster);
        if (_value > _fee) {
            payable(msg.sender).sendValue(_value - _fee);
        }
        emit BoosterCreated(msg.sender, booster, _fee);
    }

    function transferBoosterOwnership(address newOwner) external override {
        address booster = _msgSender();
        require(isBooster(booster), "NB");
        _ownerBoosters[OwnableUpgradeable(booster).owner()].remove(booster);
        _ownerBoosters[newOwner].add(booster);
    }

    function addUserBooster(address user) external override {
        address booster = _msgSender();
        require(isBooster(booster), "NB");
        _userBoosters[user].add(booster);
    }

    function removeUserBooster(address user) external override {
        address booster = _msgSender();
        require(isBooster(booster), "NB");
        _userBoosters[booster].remove(user);
    }

    function transferUserBooster(address oldUser, address newUser)
        external
        override
    {
        address booster = _msgSender();
        require(isBooster(booster), "NB");
        _userBoosters[oldUser].remove(booster);
        _userBoosters[newUser].add(booster);
    }

    // #region public external view functions.

    /// @notice get a list of boosters created by this factory
    /// @param startIndex_ start index
    /// @param endIndex_ end index
    /// @return boosters list of all created boosters.
    function boosters(uint256 startIndex_, uint256 endIndex_)
        external
        view
        override
        returns (address[] memory)
    {
        require(startIndex_ < endIndex_, "SI");
        require(endIndex_ <= numBoosters(), "EI");
        address[] memory vs = new address[](endIndex_ - startIndex_);
        for (uint256 i = startIndex_; i < endIndex_; i++) {
            vs[i] = _boosters.at(i);
        }

        return vs;
    }

    /// @notice get a list of owner boosters created by this factory
    /// @param owner An owner address
    /// @param startIndex_ start index
    /// @param endIndex_ end index
    /// @return boosters list of owner created boosters.
    function ownerBoosters(
        address owner,
        uint256 startIndex_,
        uint256 endIndex_
    ) external view override returns (address[] memory) {
        require(startIndex_ < endIndex_, "SI");
        require(endIndex_ <= numOwnerBoosters(owner), "EI");
        address[] memory vs = new address[](endIndex_ - startIndex_);
        for (uint256 i = startIndex_; i < endIndex_; i++) {
            vs[i] = _ownerBoosters[owner].at(i);
        }

        return vs;
    }

    /// @notice get a list of token boosters created by this factory
    /// @param token A token address
    /// @param startIndex_ start index
    /// @param endIndex_ end index
    /// @return boosters list of all created boosters for token.
    function tokenBoosters(
        address token,
        uint256 startIndex_,
        uint256 endIndex_
    ) external view override returns (address[] memory) {
        require(startIndex_ < endIndex_, "SI");
        require(endIndex_ <= numTokenBoosters(token), "EI");
        address[] memory vs = new address[](endIndex_ - startIndex_);
        for (uint256 i = startIndex_; i < endIndex_; i++) {
            vs[i] = _tokenBoosters[token][i];
        }

        return vs;
    }

    /// @notice get a list of user deposited boosters created by this factory
    /// @param user An user address
    /// @param startIndex_ start index
    /// @param endIndex_ end index
    /// @return boosters list of user deposited boosters.
    function userBoosters(
        address user,
        uint256 startIndex_,
        uint256 endIndex_
    ) external view override returns (address[] memory) {
        require(startIndex_ < endIndex_, "SI");
        require(endIndex_ <= numUserBoosters(user), "EI");
        address[] memory vs = new address[](endIndex_ - startIndex_);
        for (uint256 i = startIndex_; i < endIndex_; i++) {
            vs[i] = _userBoosters[user].at(i);
        }

        return vs;
    }

    /// @notice numBoosters counts the total number of boosters in existence
    /// @return result total number of boosters deployed
    function numBoosters() public view override returns (uint256 result) {
        return _boosters.length();
    }

    /// @notice numOwnerBoosters counts the total number of boosters for owner
    /// @param owner An owner address
    /// @return result total owner number of boosters deployed
    function numOwnerBoosters(address owner)
        public
        view
        override
        returns (uint256 result)
    {
        return _ownerBoosters[owner].length();
    }

    /// @notice numTokenBoosters counts the deposit token booster number
    /// @param token A token address
    /// @return result total number of boosters deployed for token
    function numTokenBoosters(address token)
        public
        view
        override
        returns (uint256 result)
    {
        return _tokenBoosters[token].length;
    }

    /// @notice numUserBoosters counts the total number of boosters with user deposit
    /// @param user An owner address
    /// @return result total user number of boosters with deposit
    function numUserBoosters(address user)
        public
        view
        override
        returns (uint256 result)
    {
        return _userBoosters[user].length();
    }

    /// @notice isBooster checks for _boosters
    /// @return returns true if _booster was created by the factory
    function isBooster(address _booster) public view override returns (bool) {
        return _boosters.contains(_booster);
    }

    // #endregion public external view functions.

    // #region internal functions

    function _preDeploy(bytes calldata payaload_, bool isBeacon_)
        internal
        returns (address booster)
    {
        bytes memory data = abi.encodeWithSelector(
            IQuadratBooster.initialize.selector,
            payaload_
        );

        bytes32 salt = keccak256(
            abi.encodePacked(tx.origin, block.number, data)
        );

        booster = isBeacon_
            ? address(new BeaconProxy{salt: salt}(address(beacon), data))
            : address(
                new TransparentUpgradeableProxy{salt: salt}(
                    beacon.implementation(),
                    address(this),
                    data
                )
            );
    }

    // #endregion internal functions
}


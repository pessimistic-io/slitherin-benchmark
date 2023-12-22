//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IAlgebraFactory} from "./IAlgebraFactory.sol";
import {IUniswapV3TickSpacing} from "./IUniswapV3TickSpacing.sol";
import {IConeCamelotFactory} from "./IConeCamelotFactory.sol";
import {IConeVaultStorage} from "./IConeVaultStorage.sol";
import {ConeFactoryStorage} from "./ConeFactoryStorage.sol";
import {EIP173Proxy} from "./EIP173Proxy.sol";
import {IEIP173Proxy} from "./IEIP173Proxy.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {EnumerableSet} from "./EnumerableSet.sol";

contract ConeCamelotFactory is ConeFactoryStorage, IConeCamelotFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct VaultParams {
        address tokenA;
        address tokenB;
        address manager;
        uint16 managerFee;
        int24[] lowerTicks;
        int24[] upperTicks;
        uint256[] percentageBIPS;
    }

    constructor(address _algebraFactory) ConeFactoryStorage(_algebraFactory) {} // solhint-disable-line no-empty-blocks

    /// @notice deployVault creates a new instance of a Vault on a specified
    /// UniswapV3Pool. The msg.sender is the initial manager of the pool and will
    /// forever be associated with the Vault as it's `deployer`
    /// @param tokenA one of the tokens in the uniswap pair
    /// @param tokenB the other token in the uniswap pair
    /// @param manager address of the managing account
    /// @param managerFee proportion of earned fees that go to pool manager in Basis Points
    /// @param lowerTicks initial lower bound of the Uniswap V3 position
    /// @param upperTicks initial upper bound of the Uniswap V3 position
    /// @return pool the address of the newly created Vault (proxy)
    function deployVault(
        address tokenA,
        address tokenB,
        address manager,
        uint16 managerFee,
        int24[] calldata lowerTicks,
        int24[] calldata upperTicks,
        uint256[] calldata percentageBIPS
    ) external override onlyManager  returns (address pool) {
        return _deployVault(
            VaultParams({
                tokenA: tokenA,
                tokenB: tokenB,
                manager: manager,
                managerFee: managerFee,
                lowerTicks: lowerTicks,
                upperTicks: upperTicks,
                percentageBIPS: percentageBIPS
            })
        );
    }

    function _deployVault(VaultParams memory params) internal returns (address) {
        (address _pool, address uniPool, string memory name) =
            _preDeploy(params.tokenA, params.tokenB, params.lowerTicks, params.upperTicks);

        _initializeVault(
            _pool,
            name,
            uniPool,
            params.managerFee,
            params.lowerTicks,
            params.upperTicks,
            params.manager,
            params.percentageBIPS
        );
        _deployers.add(params.manager);
        _pools[params.manager].add(_pool);
        index += 1;
        emit PoolCreated(uniPool, params.manager, _pool);
        return _pool;
    }

    function _initializeVault(
        address _pool,
        string memory name,
        address uniPool,
        uint16 managerFee,
        int24[] memory lowerTicks,
        int24[] memory upperTicks,
        address manager,
        uint256[] memory percentageBIPS
    ) internal {
        IConeVaultStorage(_pool).initialize(
            name,
            string(abi.encodePacked("CONE-", _uint2str(index + 1))),
            uniPool,
            managerFee,
            lowerTicks,
            upperTicks,
            manager,
            percentageBIPS
        );
    }

    function _preDeploy(address tokenA, address tokenB, int24[] memory lowerTicks, int24[] memory upperTicks)
        internal
        returns (address pool, address uniPool, string memory name)
    {
        (address token0, address token1) = _getTokenOrder(tokenA, tokenB);

        pool = address(new EIP173Proxy(poolImplementation, address(this), ""));

        name = "Cone Vault V1";
        try this.getTokenName(token0, token1) returns (string memory result) {
            name = result;
        } catch {} // solhint-disable-line no-empty-blocks

        uniPool = IAlgebraFactory(factory).poolByPair(token0, token1);
        require(uniPool != address(0), "uniswap pool does not exist");
        require(_validateTickSpacing(uniPool, lowerTicks[0], upperTicks[0]), "tickSpacing mismatch for 0");
        require(_validateTickSpacing(uniPool, lowerTicks[1], upperTicks[1]), "tickSpacing mismatch for 1");
        require(_validateTickSpacing(uniPool, lowerTicks[2], upperTicks[2]), "tickSpacing mismatch for 2");
    }

    function _validateTickSpacing(address uniPool, int24 lowerTick, int24 upperTick) internal view returns (bool) {
        int24 spacing = IUniswapV3TickSpacing(uniPool).tickSpacing();
        return lowerTick < upperTick && lowerTick % spacing == 0 && upperTick % spacing == 0;
    }

    function getTokenName(address token0, address token1) external view returns (string memory) {
        string memory symbol0 = IERC20Metadata(token0).symbol();
        string memory symbol1 = IERC20Metadata(token1).symbol();

        return _append("Cone Vault V1 ", symbol0, "/", symbol1);
    }

    function upgradePools(address[] memory pools) external onlyManager {
        for (uint256 i = 0; i < pools.length; i++) {
            IEIP173Proxy(pools[i]).upgradeTo(poolImplementation);
        }
    }

    function upgradePoolsAndCall(address[] memory pools, bytes[] calldata datas) external onlyManager {
        require(pools.length == datas.length, "mismatching array length");
        for (uint256 i = 0; i < pools.length; i++) {
            IEIP173Proxy(pools[i]).upgradeToAndCall(poolImplementation, datas[i]);
        }
    }

    function makePoolsImmutable(address[] memory pools) external onlyManager {
        for (uint256 i = 0; i < pools.length; i++) {
            IEIP173Proxy(pools[i]).transferProxyAdmin(address(0));
        }
    }

    /// @notice isPoolImmutable checks if a certain Vault is "immutable" i.e. that the
    /// proxyAdmin is the zero address and thus the underlying implementation cannot be upgraded
    /// @param pool address of the Vault
    /// @return bool signaling if pool is immutable (true) or not (false)
    function isPoolImmutable(address pool) external view returns (bool) {
        return address(0) == getProxyAdmin(pool);
    }

    /// @notice getDeployers fetches all addresses that have deployed a Vault
    /// @return deployers the list of deployer addresses
    function getDeployers() public view returns (address[] memory) {
        uint256 length = numDeployers();
        address[] memory deployers = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            deployers[i] = _getDeployer(i);
        }

        return deployers;
    }

    /// @notice getPools fetches all the Vault addresses deployed by `deployer`
    /// @param deployer address that has potentially deployed Harvesters (can return empty array)
    /// @return pools the list of Vault addresses deployed by `deployer`
    function getPools(address deployer) public view returns (address[] memory) {
        uint256 length = numPools(deployer);
        address[] memory pools = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            pools[i] = _getPool(deployer, i);
        }

        return pools;
    }

    /// @notice numPools counts the total number of Harvesters in existence
    /// @return result total number of Harvesters deployed
    function numPools() public view returns (uint256 result) {
        address[] memory deployers = getDeployers();
        for (uint256 i = 0; i < deployers.length; i++) {
            result += numPools(deployers[i]);
        }
    }

    /// @notice numDeployers counts the total number of Vault deployer addresses
    /// @return total number of Vault deployer addresses
    function numDeployers() public view returns (uint256) {
        return _deployers.length();
    }

    /// @notice numPools counts the total number of Harvesters deployed by `deployer`
    /// @param deployer deployer address
    /// @return total number of Harvesters deployed by `deployer`
    function numPools(address deployer) public view returns (uint256) {
        return _pools[deployer].length();
    }

    /// @notice getProxyAdmin gets the current address who controls the underlying implementation
    /// of a Vault. For most all pools either this contract address or the zero address will
    /// be the proxyAdmin. If the admin is the zero address the pool's implementation is naturally
    /// no longer upgradable (no one owns the zero address).
    /// @param pool address of the Vault
    /// @return address that controls the Vault implementation (has power to upgrade it)
    function getProxyAdmin(address pool) public view returns (address) {
        return IEIP173Proxy(pool).proxyAdmin();
    }

    function _getDeployer(uint256 index) internal view returns (address) {
        return _deployers.at(index);
    }

    function _getPool(address deployer, uint256 index) internal view returns (address) {
        return _pools[deployer].at(index);
    }

    function _getTokenOrder(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "same token");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "no address zero");
    }

    function _append(string memory a, string memory b, string memory c, string memory d)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(a, b, c, d));
    }

    function _uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}


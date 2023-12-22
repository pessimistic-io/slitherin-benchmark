// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "./IRamsesV2Pool.sol";
import "./FixedPoint128.sol";
import "./FullMath.sol";

import "./IVotingEscrow.sol";

import "./INonfungiblePositionManager.sol";
import "./INonfungibleTokenPositionDescriptor.sol";
import "./PositionKey.sol";
import "./PoolAddress.sol";
import "./PositionManagerAux.sol";
import "./LiquidityManagement.sol";
import "./PeripheryUpgradeable.sol";
import "./Multicall.sol";
import "./ERC721PermitUpgradeable.sol";
import "./PeripheryValidation.sol";
import "./SelfPermit.sol";
import "./PoolInitializer.sol";

/// @title NFT positions
/// @notice Wraps Ramses V2 positions in the ERC721 non-fungible token interface
contract NonfungiblePositionManager is
    Initializable,
    INonfungiblePositionManager,
    Multicall,
    ERC721PermitUpgradeable,
    PeripheryUpgradeable,
    PoolInitializer,
    LiquidityManagement,
    PeripheryValidation,
    SelfPermit
{
    /// @dev IDs of pools assigned by this contract
    mapping(address => uint80) private _poolIds;

    /// @dev Pool keys by pool ID, to save on SSTOREs for position data
    mapping(uint80 => PoolAddress.PoolKey) private _poolIdToPoolKey;

    /// @dev The token ID position data
    mapping(uint256 => Position) private _positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint176 private _nextId = 1;
    /// @dev The ID of the next pool that is used for the first time. Skips 0
    uint80 private _nextPoolId = 1;

    /// @dev The address of the token descriptor contract, which handles generating token URIs for position tokens
    address private _tokenDescriptor;

    /// @dev prevents implementation from being initialized later
    constructor() initializer() {}

    function initialize(
        address _factory,
        address _WETH9,
        address _tokenDescriptor_
    ) external initializer {
        string memory name_ = "Ramses V2 Positions NFT-V1";
        string memory symbol_ = "RAM-V2-POS";
        string memory version_ = "1";

        _nextId = 1;
        _nextPoolId = 1;

        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained(name_, symbol_);
        __ERC721Permit_init_unchained(name_, version_);
        __Periphery_init_unchained(_factory, _WETH9);

        _tokenDescriptor = _tokenDescriptor_;
    }

    /// @inheritdoc INonfungiblePositionManager
    function veRam() public view virtual override returns (address) {
        return address(0xAAA343032aA79eE9a6897Dab03bef967c3289a06);
    }

    /// @inheritdoc INonfungiblePositionManager
    function positions(
        uint256 tokenId
    )
        external
        view
        override
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory position = _positions[tokenId];
        require(position.poolId != 0, "Invalid token ID");
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        return (
            position.nonce,
            position.operator,
            poolKey.token0,
            poolKey.token1,
            poolKey.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    /// @dev Caches a pool key
    function cachePoolKey(
        address pool,
        PoolAddress.PoolKey memory poolKey
    ) private returns (uint80 poolId) {
        poolId = _poolIds[pool];
        if (poolId == 0) {
            _poolIds[pool] = (poolId = _nextPoolId++);
            _poolIdToPoolKey[poolId] = poolKey;
        }
    }

    /// @inheritdoc INonfungiblePositionManager
    function mint(
        MintParams calldata params
    )
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        IRamsesV2Pool pool;
        tokenId = _nextId++;
        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                recipient: address(this),
                index: tokenId,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                veRamTokenId: 0
            })
        );

        _mint(params.recipient, tokenId);

        bytes32 positionKey = PositionKey.compute(
            address(this),
            tokenId,
            params.tickLower,
            params.tickUpper
        );
        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            ,
            ,

        ) = pool.positions(positionKey);

        // idempotent set
        uint80 poolId = cachePoolKey(
            address(pool),
            PoolAddress.PoolKey({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee
            })
        );

        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            poolId: poolId,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: feeGrowthInside0LastX128,
            feeGrowthInside1LastX128: feeGrowthInside1LastX128,
            tokensOwed0: 0,
            tokensOwed1: 0,
            veRamTokenId: 0
        });

        emit IncreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }

    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        _;
    }

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable, IERC721MetadataUpgradeable)
        returns (string memory)
    {
        require(_exists(tokenId));
        return
            INonfungibleTokenPositionDescriptor(_tokenDescriptor).tokenURI(
                this,
                tokenId
            );
    }

    // save bytecode by removing implementation of unused method
    function baseURI() public pure override returns (string memory) {}

    /// @inheritdoc INonfungiblePositionManager
    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    )
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        Position storage position = _positions[params.tokenId];

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        IRamsesV2Pool pool;
        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: poolKey.token0,
                token1: poolKey.token1,
                fee: poolKey.fee,
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                recipient: address(this),
                index: params.tokenId,
                veRamTokenId: position.veRamTokenId
            })
        );

        bytes32 positionKey = PositionKey.compute(
            address(this),
            params.tokenId,
            position.tickLower,
            position.tickUpper
        );

        // this is now updated to the current transaction
        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            ,
            ,

        ) = pool.positions(positionKey);

        position.tokensOwed0 += uint128(
            FullMath.mulDiv(
                feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                position.liquidity,
                FixedPoint128.Q128
            )
        );
        position.tokensOwed1 += uint128(
            FullMath.mulDiv(
                feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                position.liquidity,
                FixedPoint128.Q128
            )
        );

        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        position.liquidity += liquidity;

        emit IncreaseLiquidity(params.tokenId, liquidity, amount0, amount1);
    }

    /// @inheritdoc INonfungiblePositionManager
    function decreaseLiquidity(
        DecreaseLiquidityParams calldata params
    )
        external
        payable
        override
        isAuthorizedForToken(params.tokenId)
        checkDeadline(params.deadline)
        returns (uint256 amount0, uint256 amount1)
    {
        require(params.liquidity > 0);
        Position storage position = _positions[params.tokenId];

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        IRamsesV2Pool pool = IRamsesV2Pool(
            PoolAddress.computeAddress(factory, poolKey)
        );

        return PositionManagerAux.decreaseLiquidity(position, pool, params);
    }

    /// @inheritdoc INonfungiblePositionManager
    function collect(
        CollectParams calldata params
    )
        external
        payable
        override
        isAuthorizedForToken(params.tokenId)
        returns (uint256 amount0, uint256 amount1)
    {
        Position storage position = _positions[params.tokenId];

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        IRamsesV2Pool pool = IRamsesV2Pool(
            PoolAddress.computeAddress(factory, poolKey)
        );

        return PositionManagerAux.collect(position, pool, params);
    }

    /// @inheritdoc INonfungiblePositionManager
    function switchAttachment(
        uint256 tokenId,
        uint256 veRamTokenId
    ) external override isAuthorizedForToken(tokenId) {
        if (veRamTokenId != 0) {
            require(
                IVotingEscrow(veRam()).isApprovedOrOwner(
                    msg.sender,
                    veRamTokenId
                ),
                "veRam not approved"
            );
        }

        Position storage position = _positions[tokenId];

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        IRamsesV2Pool pool = IRamsesV2Pool(
            PoolAddress.computeAddress(factory, poolKey)
        );

        emit SwitchAttachment(tokenId, position.veRamTokenId, veRamTokenId);

        pool.burn(
            tokenId,
            position.tickLower,
            position.tickUpper,
            0,
            veRamTokenId
        );
    }

    /// @inheritdoc INonfungiblePositionManager
    function burn(
        uint256 tokenId
    ) external payable override isAuthorizedForToken(tokenId) {
        Position storage position = _positions[tokenId];
        require(
            position.liquidity == 0 &&
                position.tokensOwed0 == 0 &&
                position.tokensOwed1 == 0 &&
                position.veRamTokenId == 0,
            "Not cleared"
        );
        delete _positions[tokenId];
        _burn(tokenId);
    }

    function _getAndIncrementNonce(
        uint256 tokenId
    ) internal override returns (uint256) {
        return uint256(_positions[tokenId].nonce++);
    }

    /// @inheritdoc IERC721Upgradeable
    function getApproved(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable, IERC721Upgradeable)
        returns (address)
    {
        require(
            _exists(tokenId),
            "ERC721: approved query for nonexistent token"
        );

        return _positions[tokenId].operator;
    }

    /// @dev Overrides _approve to use the operator in the position, which is packed with the position permit nonce
    function _approve(
        address to,
        uint256 tokenId
    ) internal override(ERC721Upgradeable) {
        _positions[tokenId].operator = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./Initializable.sol";
import "./IERC721.sol";
import "./Multicall.sol";
import "./EntityUtils.sol";
import "./Sample.sol";
import "./SpatialSystem.sol";
import "./MiningSystem.sol";
import "./IERC20Resource.sol";
import "./IMiaocraft.sol";
import "./constants.sol";

struct EmissionInfo {
    uint128 seed;
    uint128 amount;
}

struct AsteroidInfo {
    address resource;
    uint256 initialSupply;
    uint256 rewardPerSecond;
    int256 x;
    int256 y;
}

struct AsteroidInfoExtended {
    uint256 id;
    uint128 emissionId;
    uint32 index;
    bool identified;
    AsteroidInfo asteroidInfo;
    MineInfo mineInfo;
}

contract GenesisGalaxy is
    SpatialSystem,
    MiningSystem,
    Initializable,
    Ownable,
    Multicall
{
    uint256 public immutable ASTEROIDS_PER_EMISSION;
    uint256 public immutable MAX_DEPLETION_INTERVAL;
    uint256 public immutable MAX_RADIUS;
    uint256 public immutable SPEED; // per second

    IERC20Resource public butter;
    IMiaocraft public miaocraft;
    address public sbh;

    EmissionInfo[] public _emissionInfos;
    mapping(uint256 => uint256) public identifiedBitmaps;

    constructor(
        uint256 asteroidsPerEmission,
        uint256 maxDepletionInterval,
        uint256 maxRadius,
        uint256 speed
    ) {
        ASTEROIDS_PER_EMISSION = asteroidsPerEmission;
        MAX_DEPLETION_INTERVAL = maxDepletionInterval;
        MAX_RADIUS = maxRadius;
        SPEED = speed;
    }

    function initialize(
        address butter_,
        address miaocraft_,
        address sbh_
    ) public initializer {
        butter = IERC20Resource(butter_);
        miaocraft = IMiaocraft(miaocraft_);
        sbh = sbh_;

        // initialize the origin
        _add(getOrigin());

        _transferOwnership(msg.sender);
    }

    function getEmission(uint256 emissionId)
        public
        view
        returns (EmissionInfo memory emissionInfo)
    {
        emissionInfo = _emissionInfos[emissionId];
    }

    function getEmissionCount() public view returns (uint256) {
        return _emissionInfos.length;
    }

    function getAsteroids(uint256 emissionId)
        public
        view
        returns (AsteroidInfo[] memory asteroidInfos)
    {
        asteroidInfos = new AsteroidInfo[](ASTEROIDS_PER_EMISSION);
        for (uint256 i = 0; i < ASTEROIDS_PER_EMISSION; i++) {
            asteroidInfos[i] = getAsteroid(emissionId, i);
        }
    }

    function getAsteroid(uint256 emissionId, uint256 index)
        public
        view
        returns (AsteroidInfo memory asteroidInfo)
    {
        uint256 seed = uint256(
            keccak256(abi.encodePacked(_emissionInfos[emissionId].seed, index))
        );

        // Although sqrt(1/(1e-18 + x)) is bounded, a manipulated vrf can force
        // the multiplier to go to 1e9, which destroys the econmomy in an
        // instant. So use sqrt(1/(1e-15 + x)) to cap the multiplier at 31.6
        uint256 initialSupply = (sampleInvSqrt(seed++, 1e15) *
            _emissionInfos[emissionId].amount) /
            1e18 /
            ASTEROIDS_PER_EMISSION;

        // min reward rate is 1/2 the supply / depletion interval. Multiply b 2
        // so that the min reward rate is supply / depletion interval.
        uint256 rewardPerSecond = (2 *
            (sampleInvSqrt(seed++, 1e15) * initialSupply)) /
            1e18 /
            MAX_DEPLETION_INTERVAL;

        (int256 x, int256 y) = sampleCircle(
            seed,
            MAX_RADIUS / ASTEROID_COORD_PRECISION
        );

        asteroidInfo = AsteroidInfo({
            resource: address(butter),
            initialSupply: initialSupply,
            rewardPerSecond: rewardPerSecond,
            x: x * int256(ASTEROID_COORD_PRECISION),
            y: y * int256(ASTEROID_COORD_PRECISION)
        });
    }

    function getAsteroidExtended(uint256 emissionId, uint256 index)
        public
        view
        returns (AsteroidInfoExtended memory)
    {
        return
            _getAsteroidExtended(
                emissionId,
                index,
                identifiedBitmaps[emissionId]
            );
    }

    function getOrigin() public view returns (AsteroidInfo memory) {
        uint256 genesisCost = GENESIS_SUPPLY *
            miaocraft.buildCost(SPINS_PRECISION);
        return
            AsteroidInfo({
                resource: address(butter),
                initialSupply: 100 * genesisCost,
                rewardPerSecond: genesisCost / MAX_DEPLETION_INTERVAL,
                x: 0,
                y: 0
            });
    }

    function getOriginExtended()
        public
        view
        returns (AsteroidInfoExtended memory)
    {
        return
            AsteroidInfoExtended({
                id: 0,
                emissionId: 0,
                index: uint32(ASTEROIDS_PER_EMISSION),
                identified: true,
                asteroidInfo: getOrigin(),
                mineInfo: getMineInfo(tokenToEntity(address(this), 0))
            });
    }

    function coordinateToAsteroidId(int256 x, int256 y)
        public
        pure
        returns (uint256)
    {
        x /= int256(ASTEROID_COORD_PRECISION);
        y /= int256(ASTEROID_COORD_PRECISION);
        return
            (uint256(x < 0 ? -x + ASTEROID_COORD_NEG_FLAG : x) *
                uint256(ASTEROID_COORD_NEG_FLAG * 10)) +
            (uint256(y < 0 ? -y + ASTEROID_COORD_NEG_FLAG : y));
    }

    function asteroidIdToCoordinate(uint256 asteroidId)
        public
        pure
        returns (int256 x, int256 y)
    {
        x = int256(asteroidId) / ASTEROID_COORD_NEG_FLAG / 10;
        y = int256(asteroidId) - x * ASTEROID_COORD_NEG_FLAG * 10;
        x =
            (
                x / ASTEROID_COORD_NEG_FLAG == 0
                    ? x
                    : -(x - ASTEROID_COORD_NEG_FLAG)
            ) *
            int256(ASTEROID_COORD_PRECISION);
        y =
            (
                y / ASTEROID_COORD_NEG_FLAG == 0
                    ? y
                    : -(y - ASTEROID_COORD_NEG_FLAG)
            ) *
            int256(ASTEROID_COORD_PRECISION);
    }

    function identified(uint256 emissionId, uint256 index)
        public
        view
        returns (bool)
    {
        return _mapped(identifiedBitmaps[emissionId], index);
    }

    function _getAsteroidExtended(
        uint256 emissionId,
        uint256 index,
        uint256 identifiedBitmap
    ) internal view returns (AsteroidInfoExtended memory info) {
        AsteroidInfo memory asteroidInfo = getAsteroid(emissionId, index);
        uint256 asteroidId = coordinateToAsteroidId(
            asteroidInfo.x,
            asteroidInfo.y
        );
        return
            AsteroidInfoExtended({
                id: asteroidId,
                emissionId: uint128(emissionId),
                index: uint32(index),
                identified: _mapped(identifiedBitmap, index),
                asteroidInfo: asteroidInfo,
                mineInfo: getMineInfo(tokenToEntity(address(this), asteroidId))
            });
    }

    function _getAsteroidId(uint256 emissionId, uint256 index)
        internal
        view
        returns (uint256)
    {
        AsteroidInfo memory info = getAsteroid(emissionId, index);
        return coordinateToAsteroidId(info.x, info.y);
    }

    function _mapped(uint256 bitmap, uint256 index)
        private
        pure
        returns (bool)
    {
        return bitmap & (1 << index) != 0;
    }

    function _requireDocked(uint256 shipEntityId, uint256 asteroidEntityId)
        internal
        view
    {
        require(locked(shipEntityId), "Not docked");
        require(collocated(asteroidEntityId, shipEntityId), "Not docked here");
    }

    function addEmission(uint256 seed, uint256 amount) public {
        require(msg.sender == sbh, "Only sbh");
        _emissionInfos.push(
            EmissionInfo({seed: uint128(seed), amount: uint128(amount)})
        );
    }

    function identifyMultiple(uint256 emissionId, uint256[] memory indices)
        public
    {
        for (uint256 i = 0; i < indices.length; i++) {
            identify(emissionId, indices[i]);
        }
    }

    function identifyAll(uint256 emissionId) public {
        uint256 bitmap = identifiedBitmaps[emissionId];
        for (uint256 i = 0; i < ASTEROIDS_PER_EMISSION; i++) {
            if (!_mapped(bitmap, i)) identify(emissionId, i);
        }
    }

    function identify(uint256 emissionId, uint256 index)
        public
        returns (uint256 asteroidId)
    {
        require(emissionId < _emissionInfos.length, "Invalid emissionId");
        require(index < ASTEROIDS_PER_EMISSION, "Invalid index");
        require(!identified(emissionId, index), "Already identified");
        identifiedBitmaps[emissionId] |= 1 << index;

        asteroidId = _add(getAsteroid(emissionId, index));
    }

    function dock(uint256 shipId, uint256 asteroidId)
        public
        onlyApprovedOrShipOwner(shipId)
    {
        uint256 shipEntityId = tokenToEntity(address(miaocraft), shipId);
        uint256 asteroidEntityId = tokenToEntity(address(this), asteroidId);

        require(!locked(shipEntityId), "Already docked");

        _updateLocation(shipEntityId);

        require(collocated(asteroidEntityId, shipEntityId), "Out of orbit");

        _lock(shipEntityId);
        _dock(shipEntityId, asteroidEntityId, miaocraft.spinsOf(shipId));
    }

    function redock(uint256 shipId, uint256 asteroidId) public {
        uint256 shipEntityId = tokenToEntity(address(miaocraft), shipId);
        uint256 asteroidEntityId = tokenToEntity(address(this), asteroidId);

        _requireDocked(shipEntityId, asteroidEntityId);

        uint256 sharesBefore = getExtractorInfo(asteroidEntityId, shipEntityId)
            .shares;
        uint256 sharesAfter = miaocraft.spinsOf(shipId);
        if (sharesBefore > sharesAfter) {
            _undock(shipEntityId, asteroidEntityId, sharesBefore - sharesAfter);
        } else {
            _dock(shipEntityId, asteroidEntityId, sharesAfter - sharesBefore);
        }
    }

    function extract(uint256 shipId, uint256 asteroidId) public {
        _extract(
            tokenToEntity(address(miaocraft), shipId),
            tokenToEntity(address(this), asteroidId)
        );
    }

    function identifyAndDock(
        uint256 emissionId,
        uint256 index,
        uint256 shipId
    ) public {
        uint256 asteroidId;
        if (!identified(emissionId, index)) {
            asteroidId = identify(emissionId, index);
        } else {
            asteroidId = _getAsteroidId(emissionId, index);
        }
        dock(shipId, asteroidId);
    }

    function undockAndExtract(uint256 shipId, uint256 asteroidId)
        public
        onlyApprovedOrShipOwner(shipId)
    {
        uint256 shipEntityId = tokenToEntity(address(miaocraft), shipId);
        uint256 asteroidEntityId = tokenToEntity(address(this), asteroidId);

        _requireDocked(shipEntityId, asteroidEntityId);

        _undockAndExtract(
            shipEntityId,
            asteroidEntityId,
            getExtractorInfo(asteroidEntityId, shipEntityId).shares
        );
        _unlock(shipEntityId);
    }

    function emergencyUndock(uint256 shipId, uint256 asteroidId)
        public
        onlyApprovedOrShipOwner(shipId)
    {
        uint256 shipEntityId = tokenToEntity(address(miaocraft), shipId);
        _emergencyUndock(
            shipEntityId,
            tokenToEntity(address(this), asteroidId)
        );
        _unlock(shipEntityId);
    }

    function undockExtractAndMove(
        uint256 shipId,
        uint256 fromAsteroidId,
        uint256 toAsteroidId
    ) public {
        (int256 x, int256 y) = coordinate(
            tokenToEntity(address(this), toAsteroidId)
        );
        undockExtractAndMove(shipId, fromAsteroidId, x, y);
    }

    function undockExtractAndMove(
        uint256 shipId,
        uint256 asteroidId,
        int256 xDest,
        int256 yDest
    ) public onlyApprovedOrShipOwner(shipId) {
        uint256 shipEntityId = tokenToEntity(address(miaocraft), shipId);
        uint256 asteroidEntityId = tokenToEntity(address(this), asteroidId);

        _requireDocked(shipEntityId, asteroidEntityId);

        _undockAndExtract(
            shipEntityId,
            asteroidEntityId,
            getExtractorInfo(asteroidEntityId, shipEntityId).shares
        );
        _unlock(shipEntityId);
        _move(shipEntityId, xDest, yDest, SPEED);
    }

    function move(uint256 shipId, uint256 asteroidId) public {
        (int256 x, int256 y) = coordinate(
            tokenToEntity(address(this), asteroidId)
        );
        move(shipId, x, y);
    }

    function move(
        uint256 shipId,
        int256 xDest,
        int256 yDest
    ) public onlyApprovedOrShipOwner(shipId) {
        _move(tokenToEntity(address(miaocraft), shipId), xDest, yDest, SPEED);
    }

    function remove(uint256 shipId, uint256 asteroidId) public {
        try miaocraft.ownerOf(shipId) {
            revert("Ship exists");
        } catch Error(string memory reason) {
            require(
                keccak256(abi.encodePacked(reason)) ==
                    keccak256("ERC721: invalid token ID"),
                "Invalid reason"
            );
            _destroyExtractor(
                tokenToEntity(address(this), asteroidId),
                tokenToEntity(address(miaocraft), shipId)
            );
        }
    }

    function _add(AsteroidInfo memory asteroidInfo)
        internal
        returns (uint256 asteroidId)
    {
        asteroidId = coordinateToAsteroidId(asteroidInfo.x, asteroidInfo.y);
        uint256 asteroidEntityId = tokenToEntity(address(this), asteroidId);

        IERC20Resource(asteroidInfo.resource).mint(
            asteroidEntityId,
            asteroidInfo.initialSupply
        );

        _setCoordinate(asteroidEntityId, asteroidInfo.x, asteroidInfo.y);

        _add(
            asteroidEntityId,
            asteroidInfo.resource,
            asteroidInfo.rewardPerSecond
        );
    }

    modifier onlyApprovedOrShipOwner(uint256 shipId) {
        require(
            miaocraft.isApprovedOrOwner(msg.sender, shipId),
            "Only approved or owner"
        );
        _;
    }

    /*
    DATA QUERY FUNCTIONS
    */

    function paginateEmissions(uint256 offset, uint256 limit)
        public
        view
        returns (EmissionInfo[] memory emissionInfos_)
    {
        limit = Math.min(limit, _emissionInfos.length - offset);
        emissionInfos_ = new EmissionInfo[](limit);
        uint256 start = _emissionInfos.length - offset - 1;
        for (uint256 i = 0; i < limit; i++) {
            emissionInfos_[i] = _emissionInfos[start - i];
        }
    }

    function paginateAsteroids(uint256 offset, uint256 limit)
        public
        view
        returns (AsteroidInfoExtended[] memory asteroidInfos)
    {
        limit = Math.min(limit, _emissionInfos.length - offset);
        asteroidInfos = new AsteroidInfoExtended[](
            limit * ASTEROIDS_PER_EMISSION
        );
        uint256 start = _emissionInfos.length - offset - 1;
        for (uint256 i = 0; i < limit; i++) {
            uint256 emissionId = start - i;
            uint256 bitmap = identifiedBitmaps[i];
            asteroidInfos[
                emissionId * ASTEROIDS_PER_EMISSION + 0
            ] = _getAsteroidExtended(emissionId, 0, bitmap);
            asteroidInfos[
                emissionId * ASTEROIDS_PER_EMISSION + 1
            ] = _getAsteroidExtended(emissionId, 1, bitmap);
            asteroidInfos[
                emissionId * ASTEROIDS_PER_EMISSION + 2
            ] = _getAsteroidExtended(emissionId, 2, bitmap);
            asteroidInfos[
                emissionId * ASTEROIDS_PER_EMISSION + 3
            ] = _getAsteroidExtended(emissionId, 3, bitmap);
            asteroidInfos[
                emissionId * ASTEROIDS_PER_EMISSION + 4
            ] = _getAsteroidExtended(emissionId, 4, bitmap);
            asteroidInfos[
                emissionId * ASTEROIDS_PER_EMISSION + 5
            ] = _getAsteroidExtended(emissionId, 5, bitmap);
            asteroidInfos[
                emissionId * ASTEROIDS_PER_EMISSION + 6
            ] = _getAsteroidExtended(emissionId, 6, bitmap);
            asteroidInfos[
                emissionId * ASTEROIDS_PER_EMISSION + 7
            ] = _getAsteroidExtended(emissionId, 7, bitmap);
            asteroidInfos[
                emissionId * ASTEROIDS_PER_EMISSION + 8
            ] = _getAsteroidExtended(emissionId, 8, bitmap);
            asteroidInfos[
                emissionId * ASTEROIDS_PER_EMISSION + 9
            ] = _getAsteroidExtended(emissionId, 9, bitmap);
            asteroidInfos[
                emissionId * ASTEROIDS_PER_EMISSION + 10
            ] = _getAsteroidExtended(emissionId, 10, bitmap);
        }
    }

    /*
    OWNER FUNCTIONS
    */

    function setButter(IERC20Resource butter_) public onlyOwner {
        butter = butter_;
    }

    function setMiaocraft(IMiaocraft miaocraft_) public onlyOwner {
        miaocraft = miaocraft_;
    }

    function setSbh(address sbh_) public onlyOwner {
        sbh = sbh_;
    }
}


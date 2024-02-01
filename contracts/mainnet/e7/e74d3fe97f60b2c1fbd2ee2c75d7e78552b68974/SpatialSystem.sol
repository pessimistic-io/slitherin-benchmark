// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IERC721.sol";
import "./VectorWadMath.sol";
import "./EntityUtils.sol";
import "./ISpatialSystem.sol";

contract SpatialSystem is ISpatialSystem {
    mapping(uint256 => LocationInfo) private _locationInfos;

    function coordinate(uint256 entityId)
        public
        view
        virtual
        override
        returns (int256 x, int256 y)
    {
        return _coordinate(entityId);
    }

    function coordinate(address token, uint256 id)
        public
        view 
        virtual
        returns (int256 x, int256 y)
    {
        return _coordinate(tokenToEntity(token, id));
    }

    function locked(uint256 entityId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return _locationInfos[entityId].locked;
    }

    function collocated(uint256 entityId1, uint256 entityId2)
        public
        view 
        virtual
        override
        returns (bool)
    {
        (int256 x1, int256 y1) = _coordinate(entityId1);
        (int256 x2, int256 y2) = _coordinate(entityId2);
        return x1 == x2 && y1 == y2;
    }

    function collocated(
        uint256 entityId1,
        uint256 entityId2,
        uint256 radius
    ) public view virtual override returns (bool) {
        (int256 x1, int256 y1) = _coordinate(entityId1);
        (int256 x2, int256 y2) = _coordinate(entityId2);
        return
            VectorWadMath.distance(x1 * 1e18, y1 * 1e18, x2 * 1e18, y2 * 1e18) <=
            radius * 1e18;
    }

    function getLocationInfo(uint256 entityId)
        public
        view
        virtual
        override
        returns (LocationInfo memory)
    {
        return _locationInfos[entityId];
    }

    function _coordinate(uint256 entityId)
        internal
        view 
        virtual
        returns (int256 x, int256 y)
    {
        LocationInfo memory info = _locationInfos[entityId];
        // ship is only not moving if it's at its destination
        if (info.speed == 0) {
            return (info.xOrigin, info.yOrigin);
        }

        uint256 distance =
            VectorWadMath.distance(
                info.xOrigin,
                info.yOrigin,
                info.xDest,
                info.yDest
            );
        uint256 distanceTraveled = (block.timestamp - info.departureTime) *
            info.speed;

        // reached destination already
        if (distanceTraveled >= distance) {
            return (info.xDest, info.yDest);
        }

        (x, y) = VectorWadMath.scaleVector(
            info.xOrigin,
            info.yOrigin,
            info.xDest,
            info.yDest,
            int256((distanceTraveled * 1e18) / distance)
        );
    }

    function updateLocation(uint256 entityId) public virtual override {
        _updateLocation(entityId);
    }

    function updateLocation(address token, uint256 id) public virtual {
        _updateLocation(tokenToEntity(token, id));
    }

    function _move(
        uint256 entityId,
        int256 xDest,
        int256 yDest,
        uint256 speed
    ) internal virtual {
        require(!_locationInfos[entityId].locked, "Locked");
        (int256 x, int256 y) = _coordinate(entityId);
        _locationInfos[entityId] = LocationInfo({
            // update origin to current coordinate
            xOrigin: int40(x),
            yOrigin: int40(y),
            // set destination
            xDest: int40(xDest),
            yDest: int40(yDest),
            speed: uint40(speed),
            departureTime: uint40(block.timestamp),
            locked: false
        });

        emit Move(
            entityId,
            x,
            y,
            xDest,
            yDest,
            speed,
            block.timestamp
        );
    }

    function _updateLocation(uint256 entityId) internal virtual {
        (int256 x, int256 y) = _coordinate(entityId);
        
        LocationInfo memory info = _locationInfos[entityId];
        // arrived, so set speed to 0
        if (
            x == info.xDest &&
            y == info.yDest
        ) {
            info.speed = 0;
        }

        // update origin to current coordinate
        info.xOrigin = int40(x);
        info.yOrigin = int40(y);
        info.departureTime = uint40(block.timestamp);

        _locationInfos[entityId] = info;
        
        emit UpdateLocation(
            entityId,
            x,
            y,
            info.xDest,
            info.yDest,
            info.speed,
            block.timestamp
        );
    }

    function _setLocation(
        uint256 entityId, 
        LocationInfo memory info
    ) internal virtual {
        _locationInfos[entityId] = info;

        emit SetLocation(
            entityId,
            info.xOrigin,
            info.yOrigin,
            info.xDest,
            info.yDest,
            info.speed,
            info.departureTime
        );
    }

    function _setCoordinate(
        uint256 entityId,
        int256 x,
        int256 y
    ) internal virtual {
        _locationInfos[entityId] = LocationInfo({
            xOrigin: int40(x),
            yOrigin: int40(y),
            xDest: int40(x),
            yDest: int40(y),
            speed: 0,
            departureTime: uint40(block.timestamp),
            locked: false
        });

        emit SetCoordinate(entityId, x, y);
    }

    function _lock(
        uint256 entityId
    ) internal virtual {
        require(_locationInfos[entityId].speed == 0, "Moving");
        _locationInfos[entityId].locked = true;

        emit Locked(entityId);
    }

    function _unlock(
        uint256 entityId
    ) internal virtual {
        _locationInfos[entityId].locked = false;

        emit Unlocked(entityId);
    }
}


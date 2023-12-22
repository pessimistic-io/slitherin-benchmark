/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DeDeLend
 * Copyright (C) 2022 DeDeLend
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

pragma solidity 0.8.6;

import "./ERC20.sol";
import "./Ownable.sol";
import "./IAccountManagerToken.sol";
import "./IOrderBook.sol";
import "./IVault.sol";
import "./Doppelganger.sol";

contract AccountManager is
    Ownable,
    IAccountManager
{
    IAccountManagerToken public immutable accountManagerToken;
    address public ddl_gmx;
    address public immutable router;
    IVault public immutable vault;
    IPositionRouter public immutable positionRouter;
    mapping(address => address payable) public doppelgangerMap;
    struct KeyInformation {
        Symbols symbol;
        address doppelgangerContract;
        bool isLong;
        address indexToken;
        address user;
    }
    mapping(uint256 => KeyInformation) public override keyData;
    mapping(address => mapping(bool => Symbols)) public symbolByIndexToken;
    mapping(Symbols => address) public override indexTokenBySymbol;
    mapping(Symbols => bool) public permissions;
    address public manager;

    address[4] public arrLongIndexToken;
    address[4] public arrShortIndexToken;

    constructor(
        IAccountManagerToken _accountManagerToken,
        address _router, 
        IVault _vault,
        IPositionRouter _positionRouter,
        address[4] memory _arrLongIndexToken,
        address[4] memory _arrShortIndexToken,
        bool[2] memory _permissions,
        address _manager
    ) {
        accountManagerToken = _accountManagerToken;
        router = _router;
        vault = _vault;
        positionRouter = _positionRouter;
        arrLongIndexToken = _arrLongIndexToken;
        arrShortIndexToken = _arrShortIndexToken;
        symbolByIndexToken[_arrLongIndexToken[0]][true] = Symbols(0);
        symbolByIndexToken[_arrShortIndexToken[0]][false] = Symbols(1);
        permissions[Symbols(0)] = _permissions[0]; 
        permissions[Symbols(1)] = _permissions[1]; 
        indexTokenBySymbol[Symbols(0)] = _arrLongIndexToken[0];
        indexTokenBySymbol[Symbols(1)] = _arrLongIndexToken[0];
        manager = _manager;
    }

    modifier checkDoppelganger() {
        require(address(0) != doppelgangerMap[msg.sender], "you don't have Doppelganger");
        _;
    }

    function checkPermissions(address _indexToken, bool _isLong) private {
        require(permissions[symbolByIndexToken[_indexToken][_isLong]], "trading on this pair is stopped");
    }

    function setManager(address value) external onlyOwner {
        manager = value;
    }

    /**
     * @notice set new DDL_GMX address
     * @param value the address of DDL_GMX
     **/
    function setDDL_GMX(address value) external onlyOwner {
        ddl_gmx = value;
    }

    /**
     * @notice set permissions for trading pairs
     * @param symbol symbol name
     * @param value true or false 
     **/
     function setPermission(Symbols symbol, bool value) external onlyOwner {
        permissions[symbol] = value;
    }

    /**
     * @notice creates Doppelganger account for the user
     **/
    function createDoppelgangerGMX() public {
        require(
            doppelgangerMap[msg.sender] == address(0),
            "Doppelganger for this address already exist"
        );
        uint256 id = accountManagerToken.tokenId();
        accountManagerToken.addTokenId(2);
        uint256[2] memory keys;
        for (uint256 key = 0; key < 2; key++) {
            keys[key] = (id + key);
        }
        Doppelganger newContract = new Doppelganger(
            positionRouter,
            router,
            keys,
            arrLongIndexToken,
            arrShortIndexToken,
            address(this),
            address(accountManagerToken),
            ddl_gmx,
            manager
        );
        doppelgangerMap[msg.sender] =  payable(address(newContract));
        for (uint256 i = 0; i < 2; i++) {
            keyData[id + i] = KeyInformation(
                Symbols(i),
                address(newContract),
                i < 1 ? true : false,
                arrLongIndexToken[0],
                msg.sender
            );
            accountManagerToken.mint(msg.sender, id + i);
        }
    }

    /**
     * @notice returns getPositionDelta from GMX by the collateral ID
     * @param id collateral ID
     **/
    function getPositionDelta(uint256 id)
        public
        view
        override
        returns (bool isProfit, uint256 profit)
    {
        return
            vault.getPositionDelta(
                keyData[id].doppelgangerContract,
                keyData[id].isLong
                    ? keyData[id].indexToken
                    : arrShortIndexToken[0],
                keyData[id].indexToken,
                keyData[id].isLong
            );
    }

    /**
     * @notice returns getPosition by the collateral
     * @param id collateral ID
     **/
    function getPosition(uint256 id)
        public
        view
        override
        returns (
            uint256 size,
            uint256 collateral,
            uint256 averagePrice,
            uint256 entryFundingRate,
            uint256 reserveAmount,
            uint256 realisedPnl,
            bool isProfit,
            uint256 lastIncreasedTime
        )
    {
        (
            size,
            collateral,
            averagePrice,
            entryFundingRate,
            reserveAmount,
            realisedPnl,
            isProfit,
            lastIncreasedTime
        ) = vault.getPosition(
            keyData[id].doppelgangerContract,
            keyData[id].isLong
                ? keyData[id].indexToken
                : arrShortIndexToken[0],
            keyData[id].indexToken,
            keyData[id].isLong
        );
    }

    function isLong(uint256 id) public view override returns (bool) {
        return keyData[id].isLong;
    }

    /**
     * @param id position ID
     * @notice returns currentPrice for the asset
     **/
    function currentPrice(uint256 id) public view override returns (uint256) {
        if (isLong(id)) {
            return vault.getMaxPrice(keyData[id].indexToken);
        }
        return vault.getMinPrice(keyData[id].indexToken);
    }

    /**
     * @notice used to increase position on GMX
     **/
    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode
    ) external payable checkDoppelganger {
        checkPermissions(_indexToken, _isLong);
        (,,uint256 averagePrice,,,,,) = vault.getPosition(
            doppelgangerMap[msg.sender],
            _isLong ? arrShortIndexToken[0] : arrLongIndexToken[0],
            arrLongIndexToken[0],
            !_isLong
        );
        require(averagePrice == 0, "You cannot open a long/short position at the same time");
        if (!_isLong) {
            if (_path.length == 2) {
                require(_path[1] == arrShortIndexToken[0], "To open the short position, you have to use USDC as collateral");
            }
            if (_path[0] != arrShortIndexToken[0]) {
                address tokenIn = _path[0];
                _path = new address[](2);
                _path[0] = tokenIn;
                _path[1] = arrShortIndexToken[0];
            }
        }
        ERC20(_path[0]).transferFrom(
            msg.sender,
            doppelgangerMap[msg.sender],
            _amountIn
        );
        Doppelganger(doppelgangerMap[msg.sender]).createIncreasePosition{value: msg.value}(
            msg.sender,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            _referralCode,
            ddl_gmx
        );
    }

    /**
     * @notice used to increase position on GMX (only ETH)
     **/
    function createIncreasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode
    ) external payable checkDoppelganger {
        checkPermissions(_indexToken, _isLong);
        (,,uint256 averagePrice,,,,,) = vault.getPosition(
            doppelgangerMap[msg.sender],
            _isLong ? arrShortIndexToken[0] : arrLongIndexToken[0],
            arrLongIndexToken[0],
            !_isLong
        );
        require(averagePrice == 0, "You cannot open a long/short position at the same time");
        if (!_isLong) {
            if (_path.length == 2) {
                require(_path[1] == arrShortIndexToken[0], "To open the short position, you have to use USDC as collateral");
            }
            if (_path[0] != arrShortIndexToken[0]) {
                address tokenIn = _path[0];
                _path = new address[](2);
                _path[0] = tokenIn;
                _path[1] = arrShortIndexToken[0];
            }
        }
        Doppelganger(doppelgangerMap[msg.sender]).createIncreasePositionETH{value: msg.value}(
            msg.sender,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            _referralCode,
            ddl_gmx
        );
    }

    /**
     * @notice used to decrease position on GMX
     **/
    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH
    ) external payable checkDoppelganger {
        Doppelganger(doppelgangerMap[msg.sender]).createDecreasePosition{value: msg.value}(
            msg.sender,
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _minOut,
            _executionFee,
            _withdrawETH,
            ddl_gmx
        );
    }
}


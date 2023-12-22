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

pragma solidity 0.8.6||0.6.12;

import "./IPositionRouter.sol";
import "./IRouter.sol";
import "./IAccountManager.sol";
import "./IVault.sol";
import "./ERC721.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";

contract Doppelganger {
    using SafeERC20 for IERC20;

    receive() external payable{}

    IPositionRouter public positionRouter;
    mapping(address => mapping(bool => uint256)) public keyByIndexToken;
    mapping(uint256  => bool) public keys;
    ERC721 public GMXPT;
    address public immutable router;
    address[4] public indexTokenArray;
    address[4] public stablecoinsArray;
    address public accountManager;
    address public ddl_gmx;
    bool public isApproved = false;
    address public manager;

    constructor(
        IPositionRouter _positionRouter,
        address _router,
        uint256[2] memory keyArray,
        address[4] memory _indexTokenArray,
        address[4] memory _stablecoinsArray,
        address _accountManager,
        address _accountManagerToken,
        address _ddl_gmx,
        address _manager
    ) {
        positionRouter = _positionRouter;
        router = _router;
        indexTokenArray = _indexTokenArray;
        stablecoinsArray = _stablecoinsArray;
        keyByIndexToken[_indexTokenArray[0]][true] = keyArray[0];
        keyByIndexToken[_indexTokenArray[0]][false] = keyArray[1];
        keys[keyArray[0]] = true; 
        keys[keyArray[1]] = true; 
        GMXPT = ERC721(_accountManagerToken);
        accountManager = _accountManager;
        ddl_gmx = _ddl_gmx;
        manager = _manager;
    }

    function withdrawETH() public {
        require(msg.sender == manager, "you are not a manager");
        payable(manager).transfer(address(this).balance);
    }

    function withdrawERC20(address token) public {
        require(msg.sender == manager, "you are not a manager");
        ERC20(token).transfer(manager, ERC20(token).balanceOf(address(this)));
    }

    function _checkKeyAndMsgSender(address user, address _indexToken, bool _isLong) view private {
        require(
            GMXPT.ownerOf(keyByIndexToken[_indexToken][_isLong]) == user,
            "You re not the owner of the position"
        );
        require(keys[keyByIndexToken[_indexToken][_isLong]], "invalid key");
        if (msg.sender != ddl_gmx) {
            require(msg.sender == accountManager, "invalid msg.sender");
        }
    }

    function createIncreasePosition(
        address user,
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) external payable {
        _checkKeyAndMsgSender(user, _indexToken, _isLong);
        positionRouter.createIncreasePosition{value: msg.value}(
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            _referralCode,
            _callbackTarget
        );
    }

    function createIncreasePositionETH(
        address user,
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) external payable {
        _checkKeyAndMsgSender(user, _indexToken, _isLong);
        positionRouter.createIncreasePositionETH{value: msg.value}(
            _path,
            _indexToken,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            _referralCode,
            _callbackTarget
        );
    }

    function createDecreasePosition(
        address user,
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH,
        address _callbackTarget
    ) external payable {
        address keyOwner = GMXPT.ownerOf(keyByIndexToken[_indexToken][_isLong]);
        require(keyOwner == user, "You are not the owner of the position");
        if (msg.sender != ddl_gmx) {
            require(msg.sender == accountManager, "invalid msg.sender");
        }
        if (msg.sender == ddl_gmx) {
            keyOwner = address(this);
        }
        positionRouter.createDecreasePosition{value: msg.value}(
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            keyOwner,
            _acceptablePrice,
            _minOut,
            _executionFee,
            _withdrawETH,
            _callbackTarget
        );
    }

    /**
     * @param value maxUnit256
     **/
    function approveAll(uint256 value) public {
        IRouter(router).approvePlugin(address(positionRouter));
        for (uint256 i = 0; i < 4; i++) {
            ERC20(indexTokenArray[i]).approve(address(positionRouter), value);
            ERC20(indexTokenArray[i]).approve(router, value);
            ERC20(stablecoinsArray[i]).approve(address(positionRouter), value);
            ERC20(stablecoinsArray[i]).approve(router, value);
        }
        ERC20(stablecoinsArray[0]).approve(ddl_gmx, value);
        isApproved = true;
    }
}


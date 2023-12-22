// SPDX-License-Identifier: MIT
// A product of KeyofLife.fi

pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./ISolidlyRouter.sol";
import "./ISolidlyPair.sol";
import "./AuthUpgradeable.sol";
import "./SafeMath.sol";

interface IKeyToken {
    function depositAll() external;
    function deposit(uint256 _amount) external;
}
interface ISolidlyVault {
    function depositAll() external;
    function depositAllFor(address _user) external;
    function withdrawAll() external;
    function balanceOf(address _user) external view returns (uint256);
    function withdraw(uint256 _amount) external;
}

contract MintBalancerAuragi is Initializable, AuthUpgradeable {
    function _authorizeUpgrade(address) internal override onlyOwner {}
    using SafeERC20Upgradeable for IERC20Upgradeable;
    // Routes

    address public uniRouter;
    address public dexToken;
    address public keyToken;
    address public treasury;
    bool public autoLock;
    bool public autoTransfer;
    ISolidlyVault public constant LPVAULT =ISolidlyVault(0x1845FA6F8c0B27Ac72FaEED33961c192d5e4060D);
    ISolidlyPair pair;

    function initialize() external initializer {

        __UUPSUpgradeable_init();
        __AuthUpgradeable_init();

        uniRouter = 0x0FaE1e44655ab06825966a8fCE87b9e988AB6170; //AGI Router
        dexToken = 0xFF191514A9baba76BfD19e3943a4d37E8ec9a111; // AGI
        keyToken = 0x5CEaA2cf950b82952461D3880a02186B39A3D3Cb; //keyAGI
        treasury = 0x5A4A661594f978db52cD1BBEB36df05E6dd4E143;
        authorize(keyToken);
        IERC20Upgradeable(keyToken).approve(uniRouter, type(uint256).max);
        IERC20Upgradeable(dexToken).approve(uniRouter, type(uint256).max);
        IERC20Upgradeable(dexToken).approve(keyToken, type(uint256).max);
    }

    function shouldMint() public view returns (bool) {
        ISolidlyRouter.route[] memory _outputToLiquidRoute = new ISolidlyRouter.route[](1);
        _outputToLiquidRoute[0].from = dexToken;
        _outputToLiquidRoute[0].to = keyToken;
        _outputToLiquidRoute[0].stable = true;
        uint256 _in = 10**18;
        uint256 peg = ISolidlyRouter(uniRouter).getAmountsOut(_in, _outputToLiquidRoute)[_outputToLiquidRoute.length];
        if (_in > (peg * 9800 / 10000)) { // 2% under pegged
            return true;
        } else {
            return false;
        }
    }

    function lockForKeyToken(uint256 _amount) external authorized {
        IKeyToken(keyToken).deposit(_amount);
    }

    function balanceOfSolidlyToken() public view returns (uint256) {
        return IERC20Upgradeable(keyToken).balanceOf(address(this));
    }

    function keepPeg() external authorized {

        uint reserveDexToken;
        uint reserveKeyToken;
        if (pair.token1() == keyToken)
            (reserveDexToken, reserveKeyToken, ) = pair.getReserves();
        else
            (reserveKeyToken, reserveDexToken, ) = pair.getReserves();
        if (reserveKeyToken * 10100/10000 < reserveDexToken) {
            uint amount = (reserveDexToken - reserveKeyToken) / 2;
            amount=Math.min(amount,IERC20Upgradeable(keyToken).balanceOf(address(this)));
            if (amount==0) return;

            ISolidlyRouter.route[] memory _outputToLiquidRoute = new ISolidlyRouter.route[](1);
            _outputToLiquidRoute[0].from = keyToken;
            _outputToLiquidRoute[0].to = dexToken;
            _outputToLiquidRoute[0].stable = true;
            ISolidlyRouter(uniRouter).swapExactTokensForTokens
            (
                amount,
                0,
                _outputToLiquidRoute,
                address(this),
                block.timestamp
            );
        } else if (reserveDexToken * 10100/10000 < reserveKeyToken) {
            uint amount = (reserveKeyToken - reserveDexToken) / 2;
            amount=Math.min(amount,IERC20Upgradeable(dexToken).balanceOf(address(this)));
            if (amount==0) return;

            ISolidlyRouter.route[] memory _outputToLiquidRoute = new ISolidlyRouter.route[](1);
            _outputToLiquidRoute[0].from = dexToken;
            _outputToLiquidRoute[0].to = keyToken;
            _outputToLiquidRoute[0].stable = true;
            ISolidlyRouter(uniRouter).swapExactTokensForTokens
            (
                amount,
                0,
                _outputToLiquidRoute,
                address(this),
                block.timestamp
            );

        }
    }
    function inCaseTokensGetStuck(address _token, uint256 _amount, address _receiver) external onlyOwner {
        require( _token != dexToken && _token != keyToken,"Invalid token");
        if (_amount==0) _amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(_receiver, _amount);
    }

    function setPair() external onlyOwner {
        pair = ISolidlyPair(ISolidlyRouter(uniRouter).pairFor(dexToken, keyToken, true));
        IERC20Upgradeable(address(pair)).approve(address(LPVAULT), type(uint256).max);
        IERC20Upgradeable(address(pair)).approve(uniRouter,type(uint256).max);
    }

    function setAuto(bool _autoLock, bool _autoTransfer) external onlyOwner {
        autoLock = _autoLock;
        autoTransfer = _autoTransfer;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function balance() public view returns(uint256 _keyAmount, uint256 _dexAmount) {
        _keyAmount = IERC20Upgradeable(keyToken).balanceOf(address(this));
        _dexAmount = IERC20Upgradeable(dexToken).balanceOf(address(this));
    }

    function updateV2() external onlyOwner {
    }

}

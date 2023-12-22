// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./IERC4626Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IWETH.sol";
import "./VaultRouterStorage.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract VaultRouter is
    Initializable,
    OwnableUpgradeable, 
    UUPSUpgradeable,
    VaultRouterStorage
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address sGLP_
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        sGLP = IERC20MetadataUpgradeable(sGLP_);
    }

    // ADMIN METHODS

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setContract(Contracts c, address cAddress) public onlyOwner {
        require(cAddress != address(0));

        if (c == Contracts.GLPRewardRouterV2) {
            glpRewardRouterV2 = IRewardRouterV2(cAddress);
            return;
        }

        if (c == Contracts.GLPLeverageCompounder) {
            glpLeverageCompounderVault = IERC4626Upgradeable(cAddress);
            return;
        }

        if (c == Contracts.GLPBaseCompounder) {
            glpCompounderVault = IERC4626Upgradeable(cAddress);
            return;
        }
    }

    function buyGlpAndDeposit(address _token, address _vault, uint256 _amount, address _receiver) public payable returns (uint256) {
        require((msg.value > 0 && _token == address(0)) || (msg.value == 0 && _token != address(0)));
        require(_vault == address(glpLeverageCompounderVault) || _vault == address(glpCompounderVault), "Invalid vault address");

        if (msg.value > 0) {
            address weth = glpRewardRouterV2.weth();
            IWETH(weth).deposit{value: msg.value}();
            _token = weth;
            _amount = msg.value;
        } else {
            if (_amount == type(uint256).max && msg.value == 0 && _token != address(0)) {
                _amount = IERC20Upgradeable(_token).balanceOf(msg.sender);
                uint256 allowance = IERC20Upgradeable(_token).allowance(msg.sender, address(this));
                if (_amount > allowance) {
                    _amount = allowance;
                }
            }
            SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(_token), msg.sender, address(this), _amount);
        }

        SafeERC20Upgradeable.safeApprove(IERC20Upgradeable(_token), glpRewardRouterV2.glpManager(), _amount);
        uint256 glpMinted = glpRewardRouterV2.mintAndStakeGlp(_token, _amount, 1, 1);
        SafeERC20Upgradeable.safeApprove(sGLP, address(_vault), glpMinted);
        uint256 shares = IERC4626Upgradeable(_vault).deposit(glpMinted, _receiver);
        return shares;
    }
}

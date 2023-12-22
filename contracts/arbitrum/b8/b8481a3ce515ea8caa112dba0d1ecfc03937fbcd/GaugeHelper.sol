// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./Ownable.sol";
import "./SafeERC20.sol";

interface IHToken is IERC20 {
    function mint() external payable returns (uint); //CEther
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function underlying() external returns (address);
}

interface IBAMMv2 is IERC20 {
    function deposit(uint amount) external;
    function withdraw(uint numShares) external;
    function getCollateralValue() external view returns(uint);
    function collateralCount() external view returns(uint);
    function collaterals(uint index) external view returns(address);
    function fetchPrice(address collat) external view returns(uint);
}

interface IGauge is IERC20 {
    function deposit(uint _value, address to) external;
    function withdraw(uint _value) external;
}

interface IMinter {
    function mint(address gauge_addr) external;
    function mint_many(address[] memory gauge_addr) external;
    function mint_for(address gauge_addr, address _for) external;
    function toggle_approve_mint(address minting_user) external;
}

contract GaugeHelper is Ownable {
    using SafeERC20 for IERC20;    

    /// @notice Deposit the underlying token to the Hundred market, 
    ///         then deposit the hToken to the BAMM pool, 
    ///         then deposit the BAMM token to the gauge,
    ///         finally sending the gauge token to the destination address.
    /// @param underlying Underlying token to deposit, e.g. USDC.
    /// @param hToken Hundred market address, e.g. hUSDC
    /// @param bamm Bamm pool address, e.g. bhUSDC
    /// @param gauge Gauge address, e.g. bhUSDC-gauge
    /// @param underlyingAmount Underlying token shares to deposit.
    /// @param to The recipient of the gauge tokens.
    function depositUnderlyingToBammGauge(
        address underlying,
        address hToken,
        address bamm,
        address gauge, 
        uint underlyingAmount, 
        address to
    ) external {
        IERC20 Underlying = IERC20(underlying);
        Underlying.safeTransferFrom(msg.sender, address(this), underlyingAmount);
        Underlying.approve(hToken, underlyingAmount);
        IHToken HToken = IHToken(hToken);
        require(HToken.mint(underlyingAmount) == 0, ""); //0 is success
        uint hTokenBalance = HToken.balanceOf(address(this));
        HToken.approve(bamm, hTokenBalance);
        IBAMMv2 Bamm = IBAMMv2(bamm);
        Bamm.deposit(hTokenBalance);
        uint shares = Bamm.balanceOf(address(this));
        Bamm.approve(gauge, shares);
        IGauge Gauge = IGauge(gauge);
        Gauge.deposit(shares, to);
    }

    /// @notice Deposit the underlying token to the Hundred market, 
    ///         then deposit the hToken to the corresponding gauge, 
    ///         finally sending the gauge token to the destination address.
    /// @param underlying Underlying token to deposit, e.g. USDC.
    /// @param hToken Hundred market address, e.g. hUSDC
    /// @param gauge Gauge address, e.g. bhUSDC-gauge
    /// @param underlyingAmount Underlying token shares to deposit.
    /// @param to The recipient of the gauge tokens.
    function depositUnderlyingToGauge(
        address underlying,
        address hToken,
        address gauge, 
        uint underlyingAmount, 
        address to
    ) external {
        IERC20 Underlying = IERC20(underlying);
        Underlying.safeTransferFrom(msg.sender, address(this), underlyingAmount);
        Underlying.approve(hToken, underlyingAmount);
        IHToken HToken = IHToken(hToken);
        require(HToken.mint(underlyingAmount) == 0, ""); //0 is success
        uint hTokenBalance = HToken.balanceOf(address(this));
        HToken.approve(gauge, hTokenBalance);
        IGauge Gauge = IGauge(gauge);
        Gauge.deposit(hTokenBalance, to);
    }

    /// @notice Deposit the underlying token to the Hundred market, 
    ///         then deposit the hToken to the corresponding gauge, 
    ///         finally sending the gauge token to the destination address.
    /// @param hToken Hundred market address, e.g. hUSDC
    /// @param gauge Gauge address, e.g. bhUSDC-gauge
    /// @param to The recipient of the gauge tokens.
    function depositEtherToGauge(
        address hToken,
        address gauge, 
        address to
    ) external payable {
        IHToken HToken = IHToken(hToken);
        require(HToken.mint{value: msg.value}() == 0, ""); //0 is success
        uint hTokenBalance = HToken.balanceOf(address(this));
        HToken.approve(gauge, hTokenBalance);
        IGauge Gauge = IGauge(gauge);
        Gauge.deposit(hTokenBalance, to);
    }

    /// @notice Attempts to redeem an hToken to underlying and transfer the
    ///         underlying to the user. If the redeem fails, transfer the
    ///         hToken instead.
    function _tryRedeemAndTransfer(
        address hToken,
        address payable to,
        bool isCEther
    ) internal {
        IHToken HToken = IHToken(hToken);
        uint hTokenBalance = HToken.balanceOf(address(this));
        if (hTokenBalance == 0) return;
        uint result = HToken.redeem(hTokenBalance);
        if (result == 0) {
            if (isCEther) {
                to.transfer(address(this).balance);
            }
            else {
                IERC20 Underlying = IERC20(HToken.underlying());
                Underlying.safeTransfer(to, Underlying.balanceOf(address(this)));
            }
        }
        else { //Failed to redeem, send hTokens to user
            IERC20(HToken).safeTransfer(to, hTokenBalance);
        }
    }

    /// @notice Claims HND rewards for the msg.sender, transfers gauge tokens
    ///         from the sender to this contract and then withdraws the BAMM
    ///         lp tokens from the gauge, withdraws the hTokens from the BAMM
    ///         (both the BAMM's underlying token and any other liquidated hTokens),
    ///         then redeems the hTokens into underlying and transfers all to the
    ///         destination address. If there is not enough liquidity to redeem
    ///         any of the hTokens, transfers the hToken itself instead.
    /// @param minter Gauge's minter address, where HND rewards can be claimed
    /// @param gauge Gauge address, e.g. bhUSDC-gauge
    /// @param bamm Bamm pool address, e.g. bhUSDC
    /// @param hToken Hundred market address, e.g. hUSDC
    /// @param gaugeAmount Gauge tokens to withdraw.
    /// @param to The recipient of the underlying and/or hTokens.
    function withdrawFromBammGaugeToUnderlying(
        address minter,
        address gauge,
        address bamm,
        address hToken,
        uint gaugeAmount,
        address payable to,
        address hETH
    ) external {
        IMinter(minter).mint_for(gauge, msg.sender); //Requires toggle_approve_mint
        IGauge Gauge = IGauge(gauge);
        IERC20(Gauge).safeTransferFrom(msg.sender, address(this), gaugeAmount);
        Gauge.withdraw(gaugeAmount);
        IBAMMv2 Bamm = IBAMMv2(bamm);
        Bamm.withdraw(Bamm.balanceOf(address(this)));
        _tryRedeemAndTransfer(hToken, to, hToken == hETH);
        uint collateralCount = Bamm.collateralCount();
        for (uint i = 0; i < collateralCount; i++) {
            address collateral = Bamm.collaterals(i);
            _tryRedeemAndTransfer(collateral, to, collateral == hETH);
        }
    }

    /// @notice Claims HND rewards for the msg.sender, transfers gauge tokens
    ///         from the sender to this contract and then withdraws the 
    ///         hToken from the gauge, redeems the hTokens to underlying and
    ///         transfers to the destination address. If there is not enough 
    ///         liquidity to redeem the hToken, transfers the hToken itself instead.
    /// @param minter Gauge's minter address, where HND rewards can be claimed
    /// @param gauge Gauge address, e.g. bhUSDC-gauge
    /// @param hToken Hundred market address, e.g. hUSDC
    /// @param gaugeAmount Gauge tokens to withdraw.
    /// @param to The recipient of the underlying and/or hTokens.
    function withdrawFromGaugeToUnderlying(
        address minter,
        address gauge,
        address hToken,
        uint gaugeAmount,
        address payable to,
        bool isCEther
    ) external {
        IMinter(minter).mint_for(gauge, msg.sender); //Requires toggle_approve_mint
        IGauge Gauge = IGauge(gauge);
        IERC20(Gauge).safeTransferFrom(msg.sender, address(this), gaugeAmount);
        Gauge.withdraw(gaugeAmount);
        _tryRedeemAndTransfer(hToken, to, isCEther);
    }

    /// @notice Claims HND rewards for the msg.sender, transfers gauge tokens
    ///         from the sender to this contract and then withdraws the 
    ///         hToken from the source gauge, and deposits it to the 
    ///         destination gauge, on behalf of the `to` address.
    /// @param minter Gauge's minter address, where HND rewards can be claimed
    /// @param gaugeFrom Source gauge address, e.g. bhUSDC-gauge (old)
    /// @param gaugeTo Target gauge address, e.g. bhUSDC-gauge (new)
    /// @param hToken Hundred market address, e.g. hUSDC
    /// @param gaugeAmount Gauge tokens to migrate.
    /// @param to The recipient of the destination gaugeToken.
    function migrateGauge(
        address minter,
        address gaugeFrom,
        address hToken,
        address gaugeTo,
        uint gaugeAmount,
        address to
    ) external {
        IMinter(minter).mint_for(gaugeFrom, msg.sender); //Requires toggle_approve_mint
        IGauge GaugeFrom = IGauge(gaugeFrom);
        IERC20(GaugeFrom).safeTransferFrom(msg.sender, address(this), gaugeAmount);
        GaugeFrom.withdraw(gaugeAmount);
        IERC20 HToken = IERC20(hToken);
        uint hTokenBalance = HToken.balanceOf(address(this));
        HToken.approve(gaugeTo, hTokenBalance);
        IGauge GaugeTo = IGauge(gaugeTo);
        GaugeTo.deposit(hTokenBalance, to);
    }

    receive() external payable {}

    fallback() external payable {}

    function rescueErc20(address token) external {
        IERC20(token).safeTransfer(owner(), IERC20(token).balanceOf(address(this)));
    }

    function rescueETH() external {
        payable(owner()).transfer(address(this).balance);
    }
}


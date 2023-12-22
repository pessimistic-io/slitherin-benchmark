// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./UpgradeableBase.sol";
import "./IRECurveZapper.sol";
import "./ICurveGauge.sol";
import "./CheapSafeCurve.sol";
import "./ICurveStableSwap.sol";
import "./IREYIELD.sol";

using CheapSafeERC20 for IERC20;
using CheapSafeERC20 for ICurveStableSwap;

contract ArbitrumMigrator is UpgradeableBase(1)
{
    error ZeroAmount();
    error REYIELDAlreadyMigrated();

    bool public constant isArbitrumMigrator = true;

    ICurveGauge constant oldGauge = ICurveGauge(0x0304F3aAdcc16597D277c12f4b12213e1F075F80);
    ICurveStableSwap constant oldPool = ICurveStableSwap(0xd7bB79aeE866672419999a0496D99c54741D67B5);
    ICurveStableSwap constant oldBasePool = ICurveStableSwap(0x7f90122BF0700F9E7e1F688fe926940E8839F353);
    IERC20 constant oldREUSD = IERC20(0x3aef260cb6A5b469f970FAe7A1e233Dbd5939378);
    IERC20 constant usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    uint256 constant oldBasePoolUSDCIndex = 0;
    
    uint256 constant reyieldTotal = 13711404 * 1 ether / 10000000; // based on 13,711,404 dollar days x 0.0000001
    uint256 constant reyieldDivisor = 7831903472;

    ICurveGauge immutable newGauge;
    IRECurveZapper immutable zapper;
    IREYIELD immutable reyield;
    mapping (address => bool) reyieldAirdropProvided;

    function checkUpgradeBase(address newImplementation)
        internal
        override
        view
    {
    }

    constructor(IRECurveZapper _zapper, IREYIELD _reyield)
    {
        zapper = _zapper;
        newGauge = _zapper.gauge();
        reyield = _reyield;
    }

    function initialize()
        public
    {
        usdc.approve(address(zapper), type(uint256).max);
    }

    function migratePermit(uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        oldGauge.permit(msg.sender, address(this), permitAmount, deadline, v, r, s);
        migrate();
    }

    function migrate()
        public
    {
        uint256 balance = oldGauge.balanceOf(msg.sender);
        if (balance == 0) { revert ZeroAmount(); }
        oldGauge.transferFrom(msg.sender, address(this), balance);
        oldGauge.claim_rewards(msg.sender);
        CheapSafeCurve.safeWithdraw(address(oldGauge), balance, false);
        {
            uint256[2] memory minAmounts;
            minAmounts[0] = 1;
            minAmounts[1] = 1;
            oldPool.remove_liquidity(balance, minAmounts);
        }        
        uint256 reusdAmount = oldREUSD.balanceOf(address(this));
        require(reusdAmount > 0, "No old REUSD");
        oldREUSD.transfer(address(0), reusdAmount);
        balance = oldBasePool.balanceOf(address(this));
        require(balance > 0, "No old base pool tokens");
        uint256 usdcAmount = CheapSafeCurve.safeRemoveLiquidityOneCoin(address(oldBasePool), usdc, oldBasePoolUSDCIndex, balance, 1, address(this));
        require(usdcAmount > 0, "No usdc");
        zapper.balancedZap(usdc, usdcAmount + reusdAmount / (10 ** 12));
        balance = newGauge.balanceOf(address(this));
        require(balance > 0, "No zapped amount");
        newGauge.transfer(msg.sender, balance);
    }

    function migrateREUSD()
        public
    {
        uint256 balance = oldREUSD.balanceOf(msg.sender);
        if (balance == 0) { revert ZeroAmount(); }
        oldREUSD.transfer(address(0), balance);
        zapper.balancedZap(usdc, balance / (10 ** 12));
        balance = newGauge.balanceOf(address(this));
        require(balance > 0, "No zapped amount");
        newGauge.transfer(msg.sender, balance);
    }

    function migrateREYIELD()
        public
    {
        uint256 amount = airdropOwed(msg.sender);
        if (amount == 0) { revert ZeroAmount(); }
        if (reyieldAirdropProvided[msg.sender]) { revert REYIELDAlreadyMigrated(); }
        reyieldAirdropProvided[msg.sender] = true;
        reyield.mint(msg.sender, amount);
    }

    function migrateREYIELDNeeded(address user)
        public
        view
        returns (bool)
    {
        return airdropOwed(user) > 0 && !reyieldAirdropProvided[user];
    }

    function airdropOwed(address user)
        private
        pure
        returns (uint256 amount)
    {
        amount = user == 0x2294640e39CD6af63507F6bCD41f02E5D0075944 ? 9873688 :
            user == 0x7ea8B9138bFf17361E9b2126e181AfEe16e98b98 ? 91672411 :
            user == 0x9266DE273D7d4D19e680782a2b0039C79Af58ca8 ? 6424944678 :
            user == 0xe328554AeBbCD385462288F1637dC320C2fdCFC6 ? 538160665 :
            user == 0xc8a34589A011F46b5a6C8218fBf4ECD8b36572BB ? 11770924 :
            user == 0x8A71A81F119d85F0750C50d3abF724817B8C7B6B ? 109570536 :
            user == 0x4429d984162e1c4c4cD1fAd6885A78f870c4b892 ? 463425052 :
            user == 0x625d7862Ab8B413F8Af8a4B66bC083756730DEc9 ? 13728535 :
            user == 0x8f19Dced2FCa33E005ab497dade2D4513c878dF1 ? 31316640 :
            user == 0x926b7739c75a21fB9B9e37769f8e935bEfc19dEd ? 17585926 :
            user == 0x77401a5492bA6Fa6a2E8F43D9D8b793F1B558c70 ? 1621294 :
            user == 0xD0289005DeFc20248297ECcA18EFa50F48dE6CAF ? 7543 :
            user == 0x0565577fA64D43465632DFaA8052Af7a9Ed2214b ? 7543 :
            user == 0x5c92AF6acF40718e739A5c6c3634522EbF99069B ? 7543 :
            user == 0x63f580901912E12cc4D20F24D1202a27B574E722 ? 7543 :
            user == 0xe3AbB37776DBa4f9ae8a3B22d4e207d557e64b62 ? 7543 :
            user == 0xddeA4D40ed42124a9B00fA69Ef2Ab7543bfC0282 ? 7543 :
            user == 0x3f95fC5412b9AA1bB3711F30C494d5861843D4CF ? 7543 :
            user == 0x780FFC709D94Cfc15B816287f7644B2B0D846Ae4 ? 161410 :
            user == 0xF467f1f46CAD3F1041c765765be2891245144F6E ? 21075038 :
            user == 0x7Aa54b96B03F52d6DA69A9DceEC57c1A5814B9C2 ? 150123 :
            user == 0x0ae98a877Fd56cd9e959b1f64E40Ed93FF0d7031 ? 96793751 : 0;
        amount = amount * reyieldTotal / reyieldDivisor;
    }
}

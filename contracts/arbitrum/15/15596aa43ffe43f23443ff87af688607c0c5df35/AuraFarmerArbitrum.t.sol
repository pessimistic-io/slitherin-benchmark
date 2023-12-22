// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./test.sol";
import "./Test.sol";
import {console} from "./console.sol";
import {IERC20} from "./IERC20.sol";
import {IDola} from "./IDola.sol";
import {ArbiGovMessengerL1} from "./ArbiGovMessengerL1.sol";
import {AuraFarmer} from "./AuraFarmer.sol";
import "./IAuraBalRewardPool.sol";
import "./IComposablePoolFactory.sol";
import "./IVault.sol";
import {AddressAliasHelper} from "./AddressAliasHelper.sol";
import {IL2GatewayRouter} from "./IL2GatewayRouter.sol";

contract MockAuraRewardPool  {
    address internal token;

    constructor(address rewardToken_) {
        token = rewardToken_;
    }   

    function rewardToken() external view returns (address) {
        return token;
    }
}

contract MockVault {
    address internal bpt;

    constructor(address mockBpt) {
        bpt = mockBpt;
    }
    function getPool(bytes32 poolId) external view returns (address, address) {
        return (bpt, address(0x0));
    }
}

contract AuraFarmerTest is Test {
    
    error ExpansionMaxLossTooHigh();
    error WithdrawMaxLossTooHigh();
    error TakeProfitMaxLossTooHigh();
    error OnlyL2Chair();
    error OnlyL2Guardian();
    error OnlyGov();
    error MaxSlippageTooHigh();
    error NotEnoughTokens();
    error NotEnoughBPT();
    error AuraWithdrawFailed();
    error NothingWithdrawn();
    error OnlyChairCanTakeBPTProfit();
    error NoProfit();
    error GettingRewardFailed();

    //L1
    IDola public DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 bpt = IERC20(0xFf4ce5AAAb5a627bf82f4A571AB1cE94Aa365eA6); // USDC-DOLA bal pool
    IERC20 bal = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 aura = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    IVault vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IAuraBalRewardPool baseRewardPool =
        IAuraBalRewardPool(0x99653d46D52eE41c7b35cbAd1aC408A00bad6A76);
    address booster = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    ArbiGovMessengerL1 arbiGovMessengerL1;

    // Arbitrum
    IDola public DOLAArbi = IDola(0x6A7661795C374c0bFC635934efAddFf3A7Ee23b6);
    IERC20 public USDCArbi = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address dolaUser = 0x052f7890E50fb5b921BCAb3B10B79a58A3B9d40f; 
    address usdcUser = 0x5bdf85216ec1e38D6458C870992A69e38e03F7Ef;
    address l2MessengerAlias;
    address l2Chair = address(0x69);
    address arbiFedL1 = address(0x23);
    IAuraBalRewardPool mockBaseRewardPoolArbi;
    IVault mockVault;
    // Actual addresses
    IL2GatewayRouter public immutable l2Gateway = IL2GatewayRouter(0x5288c571Fd7aD117beA99bF60FE0846C4E84F933); 
    address l2GatewayOutbound = 0x09e9222E96E7B4AE2a407B98d48e330053351EEe;

    // Dummy values
    bytes32 poolId =
        bytes32(
            0xff4ce5aaab5a627bf82f4a571ab1ce94aa365ea6000200000000000000000426
        );

    // Values taken from AuraFed for USDC-DOLA 0x1CD24E3FBae88BECbaFED4b8Cda765D1e6e3BC03
    uint maxLossExpansion = 13;
    uint maxLossWithdraw = 10;
    uint maxLossTakeProfit = 10;

    //Numbas
    uint dolaAmount = 1000e18;
    uint usdcAmount = 1000e6;
    //Feds
    AuraFarmer auraFarmer;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"), 93907980);

        arbiGovMessengerL1 = new ArbiGovMessengerL1(gov);
        
        l2MessengerAlias = AddressAliasHelper.applyL1ToL2Alias(address(arbiGovMessengerL1));

        mockBaseRewardPoolArbi = IAuraBalRewardPool(address(new MockAuraRewardPool(address(USDCArbi)))); // Dummy value 

        mockVault = IVault(address(new MockVault(address(USDCArbi))));
        
        AuraFarmer.InitialAddresses memory addresses = AuraFarmer.InitialAddresses(
            address(DOLAArbi),
            address(mockVault), // mock
            address(mockBaseRewardPoolArbi), // mock
            address(DOLAArbi), //bpt
            booster,
            l2Chair,
            arbiFedL1,
            address(arbiGovMessengerL1)
        );


        // Deploy Aura Farmer
        auraFarmer = new AuraFarmer(
            addresses,
            maxLossExpansion,
            maxLossWithdraw,
            maxLossTakeProfit,
            poolId
        );
    }

    function test_initialized_properly() public {
        
        assertEq(auraFarmer.l2Chair(), l2Chair);
        assertEq(auraFarmer.arbiGovMessengerL1(), address(arbiGovMessengerL1));
    }

    function test_changeL2Chair() public {
        vm.expectRevert(OnlyGov.selector);
        auraFarmer.changeL2Chair(address(0x70));

        vm.prank(l2MessengerAlias);
        auraFarmer.changeL2Chair(address(0x70));
        assertEq(auraFarmer.l2Chair(), address(0x70));
    }


    function test_setMaxLossExpansionBPS() public {
        vm.expectRevert(OnlyL2Guardian.selector);
        auraFarmer.setMaxLossExpansionBps(0);

        vm.prank(l2MessengerAlias);
        auraFarmer.setMaxLossExpansionBps(0);

        assertEq(auraFarmer.maxLossExpansionBps(), 0);

        vm.expectRevert(ExpansionMaxLossTooHigh.selector);
        vm.prank(l2MessengerAlias);
        auraFarmer.setMaxLossExpansionBps(10000);
    }

    function test_setMaxWithdrawExpansionBPS() public {
        vm.expectRevert(OnlyL2Guardian.selector);
        auraFarmer.setMaxLossWithdrawBps(0);

        vm.prank(l2MessengerAlias);
        auraFarmer.setMaxLossWithdrawBps(0);

        assertEq(auraFarmer.maxLossWithdrawBps(), 0);

        vm.expectRevert(WithdrawMaxLossTooHigh.selector);
        vm.prank(l2MessengerAlias);
        auraFarmer.setMaxLossWithdrawBps(10000);
    }

    function test_setMaxLossTakeProfit() public {
        vm.expectRevert(OnlyL2Guardian.selector);
        auraFarmer.setMaxLossTakeProfitBps(0);

        vm.prank(l2MessengerAlias);
        auraFarmer.setMaxLossTakeProfitBps(0);

        assertEq(auraFarmer.maxLossTakeProfitBps(), 0);

        vm.expectRevert(TakeProfitMaxLossTooHigh.selector);
        vm.prank(l2MessengerAlias);
        auraFarmer.setMaxLossTakeProfitBps(10000);
    }

    function test_changeArbiFedL1() public {
        vm.expectRevert(OnlyGov.selector);
        auraFarmer.changeArbiFedL1(address(0x70));
        
        assertEq(address(auraFarmer.arbiFedL1()), arbiFedL1);
       
        vm.startPrank(l2MessengerAlias); 
        auraFarmer.changeArbiFedL1(address(0x70));

        assertEq(address(auraFarmer.arbiFedL1()), address(0x70));
    }

    function test_changeArbiGovMessengerL1() public {
        vm.expectRevert(OnlyGov.selector);
        auraFarmer.changeArbiGovMessengerL1(address(0x70));

        assertEq(address(auraFarmer.arbiGovMessengerL1()), address(arbiGovMessengerL1));
        
        vm.startPrank(l2MessengerAlias); 
        auraFarmer.changeArbiGovMessengerL1(address(0x70));

        assertEq(address(auraFarmer.arbiGovMessengerL1()), address(0x70));
    }
    function test_withdrawToL1ArbiFed() public {
        vm.prank(dolaUser);
        DOLAArbi.transfer(address(auraFarmer), dolaAmount);

        vm.expectRevert(OnlyL2Chair.selector);
        auraFarmer.withdrawToL1ArbiFed(dolaAmount);

        vm.prank(l2Chair);
        auraFarmer.withdrawToL1ArbiFed(dolaAmount);

        assertEq(DOLAArbi.balanceOf(address(auraFarmer)), 0);
    }

    
    function test_withdrawTokensToL1() public {
        vm.prank(usdcUser);
        USDCArbi.transfer(address(auraFarmer), usdcAmount);

        vm.expectRevert(OnlyL2Chair.selector);
        auraFarmer.withdrawToL1ArbiFed(usdcAmount);

        vm.prank(l2Chair);
        auraFarmer.withdrawTokensToL1(address(USDC),address(USDCArbi),address(2),usdcAmount);

        assertEq(DOLAArbi.balanceOf(address(auraFarmer)), 0);
    }
}   


// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {TransparentUpgradeableProxy} from "./TransparentUpgradeableProxy.sol";
import {ERC20} from "./ERC20.sol";
import {PirexRewards} from "./PirexRewards.sol";
import {PxGmx} from "./PxGmx.sol";
import {PxERC20} from "./PxERC20.sol";
import {PirexFeesContributors} from "./PirexFeesContributors.sol";
import {PirexFees} from "./PirexFees.sol";
import {PirexGmx} from "./PirexGmx.sol";
import {AutoPxGmx} from "./AutoPxGmx.sol";
import {AutoPxGlp} from "./AutoPxGlp.sol";

contract ArbitrumDeployment {
    address public constant PIREX_CORE_MSIG =
        0x4415361B7ab26c3373d41DfFA115328518a6046a;
    address public constant PIREX_FOUNDING_TEAM_MSIG =
        0x2f5dA2A590D596238c340F023A230dbBE9468C06;
    address public constant PIREX_CORE_REWARDS_PROXY_MSIG =
        0x8d70d783c2Addd148fF85551b5dE56Fcb7a60465;
    address public constant REDACTED_TREASURY_MSIG =
        0xA722eBCCd25ADB06e5d0190B240d1f4039839822;
    address public constant REDACTED_TREASURY =
        0xA722eBCCd25ADB06e5d0190B240d1f4039839822;

    // Arbitrum WETH (cross-reference with `RewardRouterV2.weth` to verify)
    // https://arbiscan.io/address/0x82af49447d8a07e3bd95bd0d56f35241523fbab1
    address public constant ARBITRUM_WETH =
        0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    PirexRewards public pirexRewardsImplementation;
    PirexRewards public pirexRewardsProxy;
    PxGmx public pxGmx;
    PxERC20 public pxGlp;
    PirexFeesContributors public pirexFeesContributors;
    PirexFees public pirexFees;
    PirexGmx public pirexGmx;
    AutoPxGmx public autoPxGmx;
    AutoPxGlp public autoPxGlp;

    constructor() {
        // Contract deployments
        _deployRewards();
        _deployTokens();
        _deployFees();
        _deployCore();
        _deployAutoVaults();

        // Access management
        _configureTokenRoles();

        // Set fees
        _configureFees();

        // Configure rewards
        _configureRewards();
    }

    function _deployRewards() private {
        pirexRewardsImplementation = new PirexRewards();

        // Set the proxy's type to the implementation contract, since calls for verifying state (i.e. admin)
        // are delegated anyway if not called by the proxy admin
        pirexRewardsProxy = PirexRewards(
            address(
                new TransparentUpgradeableProxy(
                    address(pirexRewardsImplementation),
                    // Admin address (must be different from the owner due to how the proxy routes calls)
                    PIREX_CORE_REWARDS_PROXY_MSIG,
                    abi.encodeWithSelector(PirexRewards.initialize.selector)
                )
            )
        );
    }

    function _deployTokens() private {
        pxGmx = new PxGmx(address(pirexRewardsProxy));
        pxGlp = new PxERC20(
            address(pirexRewardsProxy),
            "Pirex GLP",
            "pxGLP",
            18
        );
    }

    function _deployFees() private {
        uint256 contributorCount = 9;
        address[] memory contributorAccounts = new address[](contributorCount);
        uint256[] memory contributorFeePercents = new uint256[](
            contributorCount
        );
        contributorAccounts[0] = 0xA722eBCCd25ADB06e5d0190B240d1f4039839822;
        contributorAccounts[1] = 0x67860C3fc68338518867BD410aeA79437072e243;
        contributorAccounts[2] = 0x58Ad343326f8eBd7d039239a246d94Aea7f54da4;
        contributorAccounts[3] = 0x5A1Edb1737e54982B7A292032271Bb6F62882135;
        contributorAccounts[4] = 0xf6de48B2E23E20a54a1677b93643E5F6cd0A6060;
        contributorAccounts[5] = 0x44f49b82d7aaA4C149F5f57f8d392421eE764355;
        contributorAccounts[6] = 0xBbEBe598D016F07B48c848f7479bB97f65914f59;
        contributorAccounts[7] = 0x36f4E1803f6fF34562dB567f347dea00DeC87246;
        contributorAccounts[8] = 0xAC8E6Ba078d5b029CE00B66CA314F131E3A35f2C;
        contributorFeePercents[0] = 43_375;
        contributorFeePercents[1] = 43_375;
        contributorFeePercents[2] = 43_375;
        contributorFeePercents[3] = 43_375;
        contributorFeePercents[4] = 22_375;
        contributorFeePercents[5] = 21_375;
        contributorFeePercents[6] = 11_375;
        contributorFeePercents[7] = 11_375;
        contributorFeePercents[8] = 10_000;

        pirexFeesContributors = new PirexFeesContributors(
            PIREX_CORE_MSIG,
            contributorAccounts,
            contributorFeePercents
        );
        pirexFees = new PirexFees(
            REDACTED_TREASURY,
            address(pirexFeesContributors),
            REDACTED_TREASURY_MSIG,
            PIREX_FOUNDING_TEAM_MSIG
        );
    }

    function _deployCore() private {
        // Reference Snapshot docs and contract for more details
        // https://docs.snapshot.org/guides/delegation
        // https://arbiscan.io/address/0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446
        address snapshotDelegateRegistry = 0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;

        // Reference GMX docs and contracts for more details
        // https://gmxio.gitbook.io/gmx/contracts
        // https://arbiscan.io/address/0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a
        // https://arbiscan.io/address/0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA
        // https://arbiscan.io/address/0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1
        // https://arbiscan.io/address/0xB95DB5B167D75e6d04227CfFFA61069348d271F5
        // https://arbiscan.io/address/0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf
        address gmx = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
        address esGmx = 0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;
        address rewardRouterV2 = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
        address glpRewardRouterV2 = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
        address stakedGlp = 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf;

        pirexGmx = new PirexGmx(
            address(pxGmx),
            address(pxGlp),
            address(pirexFees),
            address(pirexRewardsProxy),
            snapshotDelegateRegistry,
            ARBITRUM_WETH,
            gmx,
            esGmx,
            rewardRouterV2,
            glpRewardRouterV2,
            stakedGlp
        );
    }

    function _deployAutoVaults() private {
        // Cache storage reads and external contract calls to reduce gas
        address pxGmxAddr = address(pxGmx);
        address pirexGmxAddr = address(pirexGmx);
        address pirexRewardsProxyAddr = address(pirexRewardsProxy);

        autoPxGmx = new AutoPxGmx(
            ARBITRUM_WETH,
            address(pirexGmx.gmx()),
            pxGmxAddr,
            "Autocompounding pxGMX",
            "apxGMX",
            pirexGmxAddr,
            pirexRewardsProxyAddr,
            address(pirexFees)
        );
        autoPxGlp = new AutoPxGlp(
            ARBITRUM_WETH,
            address(pxGlp),
            pxGmxAddr,
            "Autocompounding pxGLP",
            "apxGLP",
            pirexGmxAddr,
            pirexRewardsProxyAddr,
            address(pirexFees)
        );
    }

    function _configureTokenRoles() private {
        address pirexGmxAddr = address(pirexGmx);

        // The minter role is the same value on both the pxGMX and pxGLP contracts
        bytes32 minterRole = pxGmx.MINTER_ROLE();

        pxGmx.grantRole(minterRole, pirexGmxAddr);
        pxGlp.grantRole(minterRole, pirexGmxAddr);
        pxGlp.grantRole(pxGlp.BURNER_ROLE(), pirexGmxAddr);

        // Grant the core Pirex multisig admin privileges
        bytes32 adminRole = pxGmx.DEFAULT_ADMIN_ROLE();

        pxGmx.grantRole(adminRole, PIREX_CORE_MSIG);
        pxGlp.grantRole(adminRole, PIREX_CORE_MSIG);

        assert(pxGmx.hasRole(adminRole, PIREX_CORE_MSIG));
        assert(pxGlp.hasRole(adminRole, PIREX_CORE_MSIG));

        // Renounce the admin role, leaving the above multisig as the sole admin
        pxGmx.renounceRole(adminRole, address(this));
        pxGlp.renounceRole(adminRole, address(this));

        assert(pxGmx.hasRole(adminRole, address(this)) == false);
        assert(pxGlp.hasRole(adminRole, address(this)) == false);
    }

    function _configureRewards() private {
        pirexRewardsProxy.setProducer(address(pirexGmx));

        ERC20 _pxGmx = pxGmx;
        ERC20 _pxGlp = pxGlp;
        ERC20 weth = ERC20(ARBITRUM_WETH);

        // Add pxGMX reward strategies: pxGMX-WETH and pxGMX-pxGMX (esGMX)
        pirexRewardsProxy.addStrategyForRewards(_pxGmx, weth);
        pirexRewardsProxy.addStrategyForRewards(_pxGmx, _pxGmx);

        // Add pxGLP reward strategies: pxGLP-WETH and pxGLP-pxGMX
        pirexRewardsProxy.addStrategyForRewards(_pxGlp, weth);
        pirexRewardsProxy.addStrategyForRewards(_pxGlp, _pxGmx);

        pirexRewardsProxy.transferOwnership(PIREX_CORE_MSIG);

        assert(pirexRewardsProxy.owner() == PIREX_CORE_MSIG);
    }

    function _configureFees() private {
        // NOTE: The fee denominators are 1e6 and 1e4 for PirexGmx and the vaults, respectively

        // 1% redemption fee
        pirexGmx.setFee(PirexGmx.Fees.Redemption, 10_000);

        // 10% reward fee
        pirexGmx.setFee(PirexGmx.Fees.Reward, 100_000);

        // Final configuration steps and ownership transfer
        pirexGmx.initializeGmxState();
        pirexGmx.setPauseState(false);
        pirexGmx.transferOwnership(PIREX_CORE_MSIG);

        // 1% withdrawal fee (benefits remaining vault depositors)
        autoPxGmx.setWithdrawalPenalty(100);
        autoPxGlp.setWithdrawalPenalty(100);

        // Transfer ownership to the protocol multisig
        autoPxGmx.transferOwnership(PIREX_CORE_MSIG);
        autoPxGlp.transferOwnership(PIREX_CORE_MSIG);

        assert(pirexGmx.owner() == PIREX_CORE_MSIG);
        assert(autoPxGmx.owner() == PIREX_CORE_MSIG);
        assert(autoPxGlp.owner() == PIREX_CORE_MSIG);
    }

    function initGmx() external {
        // Approve  the contract.
        ERC20 gmx = ERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);

        uint256 balance = gmx.balanceOf(address(this));

        gmx.approve(address(autoPxGmx), balance);

        // Deposit the GMX.
        autoPxGmx.depositGmx(balance, address(this));
    }

    function initGlp() external {
        // Approve the staked glp to auto pxGlp.
        ERC20 stakedGlp = ERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);

        // Get the msg.sender balance.
        uint256 balance = stakedGlp.balanceOf(address(this));

        // Transfer from msg.sender to this contract.
        stakedGlp.approve(address(autoPxGlp), balance);

        // Deposit the sGlp into the auto pxGlp.
        autoPxGlp.depositFsGlp(balance, address(this));
    }
}


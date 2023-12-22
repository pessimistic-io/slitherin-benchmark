pragma solidity 0.8.18;

import "./Script.sol";
import "./Test.sol";
import {TransparentUpgradeableProxy as Proxy} from "./TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "./ProxyAdmin.sol";
import {LvlBatchAuctionFactory} from "./LvlBatchAuctionFactory.sol";
import {LvlBatchAuction} from "./LvlBatchAuction.sol";
import {AuctionTreasury} from "./AuctionTreasury.sol";
import {MockERC20} from "./MockERC20.sol";

contract DeployLvlAuction is Script {
    address constant CASH_TREASURY = 0xC80D81EfF760eEF1096Ae4C33854B7782352693c;
    address constant LP_RESERVE = 0x01D4844DB17f94f476119D613AC59d683e04242e;

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        MockERC20 lvl = new MockERC20("LTEST Token", "LTEST", 18);
        MockERC20 usdt = new MockERC20("USDT", "USDT", 6);

        address proxyAdmin = 0x797b7De0e7F736930ad42a3Ef115d72972b4a661;
        AuctionTreasury _treasury = new AuctionTreasury();

        Proxy proxy = new Proxy(address(_treasury), proxyAdmin, new bytes(0));
        AuctionTreasury treasuryContract = AuctionTreasury(address(proxy));
        treasuryContract.initialize(
            CASH_TREASURY,
            LP_RESERVE,
            address(lvl),
            address(usdt)
        );

    //    lvl.mintTo(1_000_000e18, address(treasuryContract));

    //     LvlBatchAuctionFactory auctionFactory = new LvlBatchAuctionFactory(
    //         address(lvl),
    //         address(usdt),
    //         address(treasuryContract),
    //         msg.sender,
    //         1 hours,
    //         2e6
    //     );

    //     treasuryContract.setLVLAuctionFactory(address(auctionFactory));

    //     new LvlBatchAuction(
    //         address(lvl),
    //         address(usdt),
    //         1,
    //         uint64(block.timestamp + 1000),
    //         uint64(block.timestamp + 2000),
    //         2e6,
    //         5e6,
    //         3e6,
    //         msg.sender,
    //         address(treasuryContract),
    //         3600
    //     );

    //     auctionFactory.createAuction(
    //         10_000e18,
    //         uint64(block.timestamp + 3600),
    //         uint64(block.timestamp + (3600 * 3)),
    //         5e6,
    //         0
    //     );
        vm.stopBroadcast();
    }
}


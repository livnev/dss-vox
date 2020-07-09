pragma solidity ^0.5.15;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "ds-value/value.sol";

import {Vat}     from 'dss/vat.sol';
import {Vow}     from 'dss/vow.sol';
import {Cat}     from 'dss/cat.sol';
import {Spotter} from 'dss/spot.sol';
import {PipLike} from 'dss/spot.sol';
import {Flipper} from 'dss/flip.sol';
import {Flapper} from 'dss/flap.sol';
import {Flopper} from 'dss/flop.sol';
import {GemJoin} from 'dss/join.sol';

import {DssVox} from "./vox.sol";

contract Hevm {
    function warp(uint256) public;
    function store(address,bytes32,bytes32) public;
}

contract WETH {
    function deposit() public payable;
    function approve(address,uint) public;
}

contract DssVoxTest is DSTest {
    Hevm hevm;

    Vat vat;
    Vow vow;
    Cat cat;
    Spotter spot;

    struct Ilk {
        DSValue pip;
        DSToken gem;
        GemJoin gemA;
        Flipper flip;
    }

    mapping (bytes32 => Ilk) ilks;

    Flapper flap;
    Flopper flop;

    DssVox vox;

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * RAY;
    }

    function init_collateral(bytes32 name) internal returns (Ilk memory) {
        DSToken coin = new DSToken(name);
        coin.mint(20 ether);

        vat.init(name);
        vat.file(name, "line", rad(1000 ether));
        GemJoin gemA = new GemJoin(address(vat), name, address(coin));
        vat.rely(address(gemA));

        coin.approve(address(gemA));
        coin.approve(address(vat));

        DSValue pip = new DSValue();
        // initial collateral price of 5
        pip.poke(bytes32(5 * WAD));

        spot.file(name, "pip", address(pip));
        // liquidation ratio of 150%
        spot.file(name, "mat", ray(1.5 ether));
        spot.poke(name);

        Flipper flip = new Flipper(address(vat), name);
        vat.hope(address(flip));
        flip.rely(address(cat));
        cat.file(name, "flip", address(flip));
        cat.file(name, "chop", ray(1 ether));
        cat.file(name, "lump", rad(15 ether));

        ilks[name].pip = pip;
        ilks[name].gem = coin;
        ilks[name].gemA = gemA;
        ilks[name].flip = flip;

        return ilks[name];
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        vat = new Vat();

        DSToken gov = new DSToken('GOV');
        flap = new Flapper(address(vat), address(gov));
        flop = new Flopper(address(vat), address(gov));

        vow = new Vow(address(vat), address(flap), address(flop));

        cat = new Cat(address(vat));
        cat.file("vow", address(vow));

        spot = new Spotter(address(vat));
        vat.rely(address(spot));

        vox = new DssVox(address(spot));
        spot.rely(address(vox));
    }

    function test_prod_noop() public {
        Ilk memory gold = init_collateral("gold");
        vox.prod();
    }

    function test_prod_basic() public {
        Ilk memory gold = init_collateral("gold");
        vox.prod();
        vox.file("way", 999985751964174351454691119);  // -5% per hour

        hevm.warp(now + 1 hours);
        vox.prod();
        assertEq(spot.par() / 10 ** 9, 0.95 ether);
    }

    function test_prod_cap() public {
        test_prod_basic();
        vox.file("way", 1000026475400412873478971742);  // +10% per hour

        assertEq(spot.par() / 10 ** 9, 0.95 ether);
        hevm.warp(now + 1 hours);
        vox.prod();
        // par is capped at 1
        assertEq(spot.par(), RAY);
    }
}

contract MainnetVoxTest is DSTest {
    Hevm    hevm;

    Vat     vat;
    Spotter spot;
    DssVox  vox;

    WETH    weth;
    GemJoin eth;
    address self;

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * RAY;
    }

    constructor() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);
        self = address(this);
    }

    function setUp() public {
        // Mainnet addresses
        vat  = Vat(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        spot = Spotter(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
        weth = WETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        eth  = GemJoin(0x2F0b23f53734252Bda2277357e97e1517d6B042A);

        // gain root over the spot
        assertEq(spot.wards(address(this)), 0);
        hevm.store(address(spot),
                   keccak256(abi.encode(address(this), uint(0))),
                   bytes32(uint(1)));
        assertEq(spot.wards(address(this)), 1);

        // install the vox
        vox = new DssVox(address(spot));
        spot.rely(address(vox));

        // install our own oracle for easier calculations
        DSValue pip = new DSValue();
        spot.file("ETH-A", "pip", address(pip));
        pip.poke(bytes32(300 * WAD));
        spot.poke("ETH-A");

        // get some eth collateral
        weth.deposit.value(100 ether)();
        weth.approve(address(eth), uint(-1));
        eth.join(address(this), 100 ether);
    }

    function try_call(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas, addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }
    function can_frob(bytes32 ilk, address u, address v, address w, int dink, int dart) public returns (bool) {
        string memory sig = "frob(bytes32,address,address,address,int256,int256)";
        bytes memory data = abi.encodeWithSignature(sig, ilk, u, v, w, dink, dart);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", vat, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_draw(bytes32 ilk, uint wad) public returns (bool) {
        (uint A, uint rate, uint s, uint l, uint d) = vat.ilks("ETH-A"); A;s;l;d;
        return this.can_frob(ilk, self, self, self, 0, int(rad(wad) / rate));
    }
    function lock(bytes32 ilk, uint wad) public {
        vat.frob(ilk, self, self, self, int(wad), 0);
    }

    function test_mainnet_target_adjustment() public {
        lock("ETH-A", 100 ether);
        // normally we can draw this much (mat is 150%)
        assertTrue( can_draw("ETH-A", 20000 ether) );

        // we can't draw excess
        assertTrue(!can_draw("ETH-A", 20001 ether) );

        // now tick forward 1 hour at -5%/hour
        vox.file("way", ray(0.9999857519641744 ether));
        hevm.warp(now + 1 hours);
        vox.prod(); spot.poke("ETH-A");  // (have to prod to update)

        // the value of debt has decreased and we can draw
        // more dai (1 / 0.95 extra)
        assertTrue( can_draw("ETH-A", 20000 ether) );
        assertTrue( can_draw("ETH-A", 21052 ether) );
        assertTrue(!can_draw("ETH-A", 21053 ether) );

        // tick forward another hour
        hevm.warp(now + 1 hours);
        vox.prod(); spot.poke("ETH-A");
        // dai is now even cheaper
        assertTrue( can_draw("ETH-A", 22160 ether) );
        assertTrue(!can_draw("ETH-A", 22161 ether) );

        // now let's change to +5% / hour
        vox.file("way", 1000013552915220323465053052);
        hevm.warp(now + 1 hours);
        vox.prod(); spot.poke("ETH-A");
        assertTrue( can_draw("ETH-A", 21105 ether) );
        assertTrue(!can_draw("ETH-A", 21106 ether) );

        // and again, nearly returning to starting point
        hevm.warp(now + 1 hours);
        vox.prod(); spot.poke("ETH-A");
        assertTrue( can_draw("ETH-A", 20100 ether) );
        assertTrue(!can_draw("ETH-A", 20101 ether) );

        // we can't exceed the cap, which defaults to 1
        hevm.warp(now + 1 hours);
        vox.prod(); spot.poke("ETH-A");
        assertTrue( can_draw("ETH-A", 20000 ether) );
        assertTrue(!can_draw("ETH-A", 20001 ether) );
    }
}

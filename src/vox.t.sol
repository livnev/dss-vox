pragma solidity ^0.5.15;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "ds-value/value.sol";

import {Vat} from 'dss/vat.sol';
import {Vow}     from 'dss/vow.sol';
import {Cat}     from 'dss/cat.sol';
import {Spotter} from 'dss/spot.sol';
import {Flipper} from 'dss/flip.sol';
import {Flapper} from 'dss/flap.sol';
import {Flopper} from 'dss/flop.sol';
import {GemJoin} from 'dss/join.sol';

import {DssVox} from "./vox.sol";

contract Hevm {
    function warp(uint256) public;
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
    }

    function test_prod_basic() public {
        Ilk memory gold = init_collateral("gold");
        vox.prod();
    }
}

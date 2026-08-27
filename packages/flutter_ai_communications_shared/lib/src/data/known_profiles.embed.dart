/// Embedded copy of `known_profiles.json`. Tests require these to match.
const String knownProfilesJson = r'''
[
  {
    "id": "airpods-pro",
    "aliases": ["airpods pro"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://www.apple.com/airpods/compare/"
    ]
  },
  {
    "id": "airpods-max",
    "aliases": ["airpods max"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://www.apple.com/airpods/compare/"
    ]
  },
  {
    "id": "airpods",
    "aliases": ["airpods"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://www.apple.com/airpods/compare/"
    ]
  },
  {
    "id": "sony-wh-1000x",
    "aliases": ["wh-1000xm5", "wh-1000xm4", "wh-1000xm3", "sony wh-1000"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://www.sony.com/electronics/support/wireless-headphones-bluetooth-headphones/wh-1000xm5/specifications"
    ]
  },
  {
    "id": "sony-wf-1000x",
    "aliases": ["wf-1000xm5", "wf-1000xm4", "sony wf-1000"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://www.sony.com/electronics/support/wireless-headphones-bluetooth-headphones/wh-1000xm5/specifications"
    ]
  },
  {
    "id": "bose-quietcomfort",
    "aliases": ["bose quietcomfort", "bose qc45", "bose qc 45", "quietcomfort ultra", "quietcomfort 45"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://www.bose.com/pressroom/bose-introduces-quietcomfort-45"
    ]
  },
  {
    "id": "beats-fit-pro",
    "aliases": ["beats fit pro"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://www.apple.com/airpods/compare/"
    ]
  },
  {
    "id": "sennheiser-momentum",
    "aliases": ["sennheiser momentum"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://www.sennheiser.com/en-us/catalog/products/headphones/momentum-4-wireless"
    ]
  },
  {
    "id": "soundcore-space",
    "aliases": ["soundcore space"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://www.soundcore.com/products/a3033"
    ]
  },
  {
    "id": "jabra-evolve2-65-flex",
    "aliases": ["evolve2 65 flex"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://www.broadbandbuyer.com/advice/4729-jabra-evolve2-headset-comparison-chart/"
    ]
  },
  {
    "id": "jabra-evolve2-anc",
    "aliases": ["evolve2 75", "evolve2 85", "evolve2 55", "evolve2 50"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://www.pcmag.com/reviews/jabra-evolve2-75",
      "https://www.broadbandbuyer.com/advice/4729-jabra-evolve2-headset-comparison-chart/"
    ]
  },
  {
    "id": "jabra-evolve2-65",
    "aliases": ["evolve2 65"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://www.amazon.com/Jabra-Bluetooth-Wireless-Headphones-Noise-Cancelling/dp/B0GHFLJQB3"
    ]
  },
  {
    "id": "poly-voyager-focus",
    "aliases": ["voyager focus"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://headsetadvisor.com/products/poly-voyager-focus-uc-2-wireless-headset-with-anc"
    ]
  },
  {
    "id": "pixel-buds-pro",
    "aliases": ["pixel buds pro", "pixel buds 2a"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://blog.google/products-and-platforms/devices/pixel/pixel-buds-pro-io-2022/",
      "https://support.google.com/googlepixelbuds/answer/15437068"
    ]
  },
  {
    "id": "galaxy-buds-anc",
    "aliases": ["galaxy buds pro", "galaxy buds2", "galaxy buds 2", "galaxy buds fe"],
    "family": "communicationsHeadset",
    "hardwareNoiseProcessing": true,
    "sources": [
      "https://www.samsung.com/us/mobile/audio/galaxy-buds/"
    ]
  },
  {
    "id": "jbl-flip",
    "aliases": ["jbl flip 6", "jbl flip 5", "jbl flip"],
    "family": "bluetoothSpeaker",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://manuals.plus/jbl/flip6-bluetooth-speaker-manual"
    ]
  },
  {
    "id": "jbl-charge",
    "aliases": ["jbl charge", "jbl xtreme", "jbl boombox", "jbl go"],
    "family": "bluetoothSpeaker",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://www.jbl.com/bluetooth-speakers/"
    ]
  },
  {
    "id": "jabra-speak",
    "aliases": ["jabra speak2", "jabra speak"],
    "family": "bluetoothSpeaker",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://www.jabra.com/-/media/Files/Brochures/Product-Catalogue/2025/Jabra_UC_202507.pdf"
    ]
  },
  {
    "id": "tesla-model",
    "aliases": ["tesla model y", "tesla model 3", "tesla model s", "tesla model x"],
    "family": "car",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://teslamotorsclub.com/tmc/threads/bluetooth-goes-in-and-out-2-different-names-for-the-car-showing.327927/"
    ]
  },
  {
    "id": "ford-sync",
    "aliases": ["ford sync", "ford focus"],
    "family": "car",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://www.ford.ie/support/how-tos/sync/getting-started-with-sync/how-to-pair-a-phone-with-sync"
    ]
  },
  {
    "id": "uconnect",
    "aliases": ["uconnect"],
    "family": "car",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://www.mopar.com/en-us/technology/smartphone-pairing.html"
    ]
  },
  {
    "id": "carplay",
    "aliases": ["carplay"],
    "family": "car",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://developer.apple.com/forums/thread/732202"
    ]
  },
  {
    "id": "rivian-audio",
    "aliases": ["rivian audio", "rivian"],
    "family": "car",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://rivian.com/support/article/rivian-assistant"
    ]
  },
  {
    "id": "mb-bluetooth",
    "aliases": ["mb bluetooth"],
    "family": "car",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://www.mercedesmedic.com/pair-android-iphone-bluetooth-phone-with-mercedes-benz/"
    ]
  },
  {
    "id": "bmw-identity",
    "aliases": ["bmw"],
    "family": "car",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://www.youtube.com/watch?v=dx8e9X4ktlg"
    ]
  },
  {
    "id": "lucid-head-unit",
    "aliases": ["lucid"],
    "family": "car",
    "hardwareNoiseProcessing": false,
    "sources": [
      "https://lucidowners.com/threads/a-better-workaround-for-carplay-audio-choosing-the-wrong-source.8868/"
    ]
  }
]
''';

"""
Binary speaker verification MVP.

Pipeline:
  1. Extract frozen ECAPA-TDNN embeddings (SpeechBrain, pretrained on VoxCeleb)
     for target-speaker clips and non-target clips.
  2. Train a small tf.keras classifier on those embeddings.
  3. Run inference on new audio.

Install deps first:
    pip install speechbrain torch torchaudio tensorflow soundfile

Expected folder layout:
    data/
      target/        <- clips of YOU speaking (.wav, 16kHz mono ideally)
      non_target/     <- clips of other speakers / background talk

Usage:
    python speaker_id_pipeline.py train
    python speaker_id_pipeline.py predict path/to/clip.wav
"""

import os
import sys
import glob
import numpy as np
import tensorflow as tf
import torch
import torchaudio
from speechbrain.inference.speaker import EncoderClassifier

TARGET_DIR = "data/target"
NON_TARGET_DIR = "data/non_target"
EMBEDDING_DIM = 192
CLASSIFIER_PATH = "speaker_classifier.keras"
TARGET_SR = 16000

# ---------------------------------------------------------------------------
# 1. Frozen embedding extractor
# ---------------------------------------------------------------------------

_embedder = None


def get_embedder():
    """Lazily load the pretrained ECAPA-TDNN model (downloads on first run)."""
    global _embedder
    if _embedder is None:
        _embedder = EncoderClassifier.from_hparams(
            source="speechbrain/spkrec-ecapa-voxceleb",
            savedir="pretrained_models/spkrec-ecapa-voxceleb",
        )
    return _embedder


def load_waveform(path):
    """Load audio and resample to 16kHz mono, which ECAPA-TDNN expects."""
    waveform, sr = torchaudio.load(path)
    if waveform.shape[0] > 1:  # stereo -> mono
        waveform = waveform.mean(dim=0, keepdim=True)
    if sr != TARGET_SR:
        waveform = torchaudio.functional.resample(waveform, sr, TARGET_SR)
    return waveform


def embed_file(path):
    """Return a 192-dim numpy embedding for one audio file."""
    embedder = get_embedder()
    waveform = load_waveform(path)
    with torch.no_grad():
        emb = embedder.encode_batch(waveform)  # shape [1, 1, 192]
    return emb.squeeze().cpu().numpy()


def embed_folder(folder):
    paths = sorted(glob.glob(os.path.join(folder, "*.wav")))
    if not paths:
        raise ValueError(f"No .wav files found in {folder}")
    embeddings = []
    for p in paths:
        print(f"  embedding {p}")
        embeddings.append(embed_file(p))
    return np.stack(embeddings)


# ---------------------------------------------------------------------------
# 2. Classifier
# ---------------------------------------------------------------------------


def build_classifier():
    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(EMBEDDING_DIM,)),
        tf.keras.layers.Dense(64, activation="relu"),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(1, activation="sigmoid"),
    ])
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss="binary_crossentropy",
        metrics=["accuracy"],
    )
    return model


def train():
    print("Extracting embeddings for target speaker...")
    target_emb = embed_folder(TARGET_DIR)
    print("Extracting embeddings for non-target speakers...")
    non_target_emb = embed_folder(NON_TARGET_DIR)

    X = np.concatenate([target_emb, non_target_emb], axis=0)
    y = np.concatenate([
        np.ones(len(target_emb)),
        np.zeros(len(non_target_emb)),
    ])

    # shuffle
    idx = np.random.permutation(len(X))
    X, y = X[idx], y[idx]

    model = build_classifier()
    model.fit(
        X, y,
        epochs=30,
        batch_size=8,
        validation_split=0.2,
        verbose=2,
    )
    model.save(CLASSIFIER_PATH)
    print(f"Saved classifier to {CLASSIFIER_PATH}")


# ---------------------------------------------------------------------------
# 3. Inference
# ---------------------------------------------------------------------------


def predict(path, threshold=0.5):
    model = tf.keras.models.load_model(CLASSIFIER_PATH)
    emb = embed_file(path).reshape(1, -1)
    prob = float(model.predict(emb, verbose=0)[0, 0])
    label = "TARGET SPEAKER" if prob >= threshold else "NOT TARGET SPEAKER"
    print(f"{path}: p(target)={prob:.3f} -> {label}")
    return prob


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "train":
        train()
    elif cmd == "predict":
        if len(sys.argv) < 3:
            print("Usage: python speaker_id_pipeline.py predict path/to/clip.wav")
            sys.exit(1)
        predict(sys.argv[2])
    else:
        print(f"Unknown command: {cmd}")
        print(__doc__)
package com.google.android.play.core.tasks;

public class Task<ResultT> {
    public Task<ResultT> addOnSuccessListener(OnSuccessListener<? super ResultT> listener) {
        return this;
    }

    public Task<ResultT> addOnFailureListener(OnFailureListener listener) {
        return this;
    }
}

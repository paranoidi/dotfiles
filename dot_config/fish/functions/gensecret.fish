function gensecret -d "Generate a 64-character hex secret"
    openssl rand -hex 32
end

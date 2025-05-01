<?php
include "wp-config.php";
try {
    $conn = mysqli_connect(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME);
    if (!$conn) {
        echo "Database connection failed";
        exit(1);
    }
    
    // Prepare query to prevent SQL injection
    $stmt = mysqli_prepare($conn, "SELECT option_value FROM {TABLE_PREFIX}options WHERE option_name = ? LIMIT 1");
    mysqli_stmt_bind_param($stmt, 's', $option_name);
    $option_name = 'blogname';
    
    if (mysqli_stmt_execute($stmt)) {
        mysqli_stmt_bind_result($stmt, $option_value);
        if (mysqli_stmt_fetch($stmt)) {
            echo $option_value;
        }
    }
    
    mysqli_stmt_close($stmt);
    mysqli_close($conn);
} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
    exit(1);
}
